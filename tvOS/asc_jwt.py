"""Mints a short-lived App Store Connect API token. Key id and issuer are not secret;
the .p8 stays in ~/.appstoreconnect/private_keys and is never printed."""
import base64, json, subprocess, time

KEY_ID = "65298RSLYG"
ISSUER = "a5f4aa01-2327-491e-b9c4-31f2e2beb63e"
KEY = f"{__import__('os').path.expanduser('~')}/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8"

def b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode().rstrip("=")

def der_to_raw(der: bytes) -> bytes:
    assert der[0] == 0x30
    i = 2 if der[1] < 0x80 else 3 + (der[1] & 0x7F) - 1
    out = b""
    for _ in range(2):
        assert der[i] == 0x02
        n = der[i + 1]
        out += der[i + 2 : i + 2 + n].lstrip(b"\x00").rjust(32, b"\x00")
        i += 2 + n
    return out

now = int(time.time())
head = b64(json.dumps({"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}, separators=(",", ":")).encode())
body = b64(json.dumps({"iss": ISSUER, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}, separators=(",", ":")).encode())
signing_input = f"{head}.{body}"
der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", KEY], input=signing_input.encode(),
                     capture_output=True, check=True).stdout
print(f"{signing_input}.{b64(der_to_raw(der))}")
