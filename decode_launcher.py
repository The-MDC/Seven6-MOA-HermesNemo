import base64

with open(r"C:\Users\nicholasjmcleod\AppData\Local\hermes\bin\hermes.cmd", "r", encoding="utf-8-sig") as f:
    content = f.read()

# extract the base64 blob between the quotes after -c
start = content.index("exec(base64.b64decode('") + len("exec(base64.b64decode('")
end = content.index("'))", start)
b64 = content[start:end]
decoded = base64.b64decode(b64).decode()
with open(r"C:\Users\nicholasjmcleod\seven6-hermes-moa\decoded_launcher.py", "w", encoding="utf-8") as out:
    out.write(decoded)
print("wrote decoded_launcher.py, length:", len(decoded))
