import ipaddress
import json
import pathlib
import socket
import struct
import subprocess
import sys
import threading
import time


def receive_exact(connection, size):
    result = b""
    while len(result) < size:
        chunk = connection.recv(size - len(result))
        if not chunk:
            raise ConnectionError("Unexpected EOF")
        result += chunk
    return result


def encode_address(host):
    try:
        address = ipaddress.ip_address(host)
    except ValueError:
        encoded = host.encode()
        return b"\x03" + bytes([len(encoded)]) + encoded
    return (b"\x01" if address.version == 4 else b"\x04") + address.packed


def read_address(connection, kind):
    if kind == 1:
        return socket.inet_ntop(socket.AF_INET, receive_exact(connection, 4))
    if kind == 4:
        return socket.inet_ntop(socket.AF_INET6, receive_exact(connection, 16))
    if kind == 3:
        return receive_exact(connection, receive_exact(connection, 1)[0]).decode()
    raise ValueError("Invalid SOCKS address type")


def socks_connection(command, host, port):
    connection = socket.create_connection(("127.0.0.1", 19080), timeout=2)
    try:
        connection.sendall(b"\x05\x01\x00")
        assert receive_exact(connection, 2) == b"\x05\x00"
        connection.sendall(b"\x05" + bytes([command]) + b"\x00" + encode_address(host) + struct.pack("!H", port))
        header = receive_exact(connection, 4)
        assert header[:2] == b"\x05\x00", header
        bound_host = read_address(connection, header[3])
        bound_port = struct.unpack("!H", receive_exact(connection, 2))[0]
        return connection, bound_host, bound_port
    except BaseException:
        connection.close()
        raise


def request_tcp(host):
    connection, _, _ = socks_connection(1, host, 19082)
    with connection:
        connection.sendall(b"GET / HTTP/1.0\r\nHost: test\r\n\r\n")
        response = b""
        while True:
            chunk = connection.recv(4096)
            if not chunk:
                break
            response += chunk
        return response.split(b"\r\n\r\n", 1)[1].decode()


def request_udp(host):
    control, bound_host, bound_port = socks_connection(3, "0.0.0.0", 0)
    with control, socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as channel:
        channel.settimeout(2)
        payload = b"\x00\x00\x00" + encode_address(host) + struct.pack("!H", 19082) + b"probe"
        channel.sendto(payload, ("127.0.0.1" if bound_host == "0.0.0.0" else bound_host, bound_port))
        response, _ = channel.recvfrom(4096)
        assert response[:3] == b"\x00\x00\x00"
        kind = response[3]
        offset = 8 if kind == 1 else 20 if kind == 4 else 5 + response[4]
        return response[offset + 2:].decode()


def start_echo(address, response, udp=False):
    family = socket.AF_INET6 if ":" in address else socket.AF_INET
    listener = socket.socket(family, socket.SOCK_DGRAM if udp else socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    if family == socket.AF_INET6:
        listener.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
    listener.bind((address, 19082))
    if not udp:
        listener.listen(16)

    def serve():
        try:
            while True:
                if udp:
                    _, peer = listener.recvfrom(4096)
                    listener.sendto(response.encode(), peer)
                else:
                    connection, _ = listener.accept()
                    with connection:
                        connection.recv(4096)
                        body = response.encode()
                        connection.sendall(b"HTTP/1.0 200 OK\r\nContent-Length: " + str(len(body)).encode() + b"\r\n\r\n" + body)
        except OSError:
            return

    threading.Thread(target=serve, daemon=True).start()
    return listener


def wait_for_listener(process, port):
    for attempt in range(100):
        if process.poll() is not None:
            raise RuntimeError("Xray exited before accepting connections")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                return
        except OSError:
            time.sleep(0.1)
    raise TimeoutError("Xray listener not ready")


binary = sys.argv[1]
artifacts = pathlib.Path(sys.argv[2])
uuid = "11111111-1111-4111-8111-111111111111"
listeners = []
results = []
try:
    for address, label in [("203.0.114.10", "ipv4"), ("203.0.114.11", "matched-ip"), ("2001:db9::10", "ipv6"), ("127.0.0.1", "private")]:
        for udp in [False, True]:
            listeners.append(start_echo(address, label, udp))
    for preference in ["ipv4", "ipv6"]:
        documents = json.loads((artifacts / (preference + "-documents.json")).read_text())
        access_path = artifacts / (preference + "-access.log")
        server = {
            **documents["routing"], **documents["outbounds"],
            "log": {"loglevel": "info", "access": str(access_path)},
            "dns": {"hosts": {"dual.test": ["203.0.114.10", "2001:db9::10"], "v4.test": "203.0.114.10", "v6.test": "2001:db9::10", "sub.warp.test": "2001:db9::10", "private.test": "127.0.0.1"}},
            "inbounds": [{"listen": "127.0.0.1", "port": 19081, "protocol": "vless", "tag": "test-vless", "settings": {"clients": [{"id": uuid}], "decryption": "none"}}],
        }
        client = {
            "log": {"loglevel": "warning"},
            "inbounds": [{"listen": "127.0.0.1", "port": 19080, "protocol": "socks", "settings": {"udp": True}}],
            "outbounds": [{"protocol": "vless", "settings": {"vnext": [{"address": "127.0.0.1", "port": 19081, "users": [{"id": uuid, "encryption": "none"}]}]}}],
        }
        processes = []
        logs = []
        try:
            for name, config, port in [("server", server, 19081), ("client", client, 19080)]:
                path = artifacts / (preference + "-" + name + ".json")
                path.write_text(json.dumps(config, indent=2))
                subprocess.run([binary, "run", "-test", "-c", str(path)], check=True, capture_output=True)
                log = (artifacts / (preference + "-" + name + ".log")).open("w")
                logs.append(log)
                process = subprocess.Popen([binary, "run", "-c", str(path)], stdout=log, stderr=log)
                processes.append(process)
                wait_for_listener(process, port)
            for protocol, request in [("tcp", request_tcp), ("udp", request_udp)]:
                for host, expected in [("dual.test", preference), ("v4.test", "ipv4"), ("v6.test", "ipv6"), ("203.0.114.10", "ipv4"), ("2001:db9::10", "ipv6"), ("sub.warp.test", "ipv6"), ("203.0.114.11", "matched-ip")]:
                    response = request(host)
                    assert response == expected, (preference, protocol, host, response, expected)
                    results.append({"preference": preference, "protocol": protocol, "host": host, "response": response})
                try:
                    response = request("private.test")
                except (OSError, ConnectionError, IndexError, AssertionError):
                    results.append({"preference": preference, "protocol": protocol, "host": "private.test", "blocked": True})
                else:
                    raise AssertionError(("Private destination not blocked", protocol, response))
        finally:
            for process in processes:
                process.terminate()
            for process in processes:
                process.wait(timeout=5)
            for log in logs:
                log.close()
        access = access_path.read_text()
        for protocol in ["tcp", "udp"]:
            tag = "warp-auto-" + ("udp-" if protocol == "udp" else "") + preference + "-first"
            for host in ["sub.warp.test", "203.0.114.11"]:
                assert any(protocol + ":" + host + ":19082" in line and "-> " + tag + "]" in line for line in access.splitlines()), (protocol, host, "WARP rule not matched")
finally:
    for listener in listeners:
        listener.close()
    (artifacts / "results.json").write_text(json.dumps(results, indent=2))

print("egress integration passed: TCP/UDP, both preferences, single-family domains, literals, domain-or-IP routing, private blocking")
