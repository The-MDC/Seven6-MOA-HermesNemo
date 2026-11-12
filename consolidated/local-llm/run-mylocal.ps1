# MyLocal: llama.cpp router (Spark + Gemma, one resident at a time)
Get-Process llama-server -ErrorAction SilentlyContinue | Stop-Process -Force
llama-server --models-preset "$env:USERPROFILE\local-llm\mylocal-models.ini" --models-max 1 --host 127.0.0.1 --port 8080 --parallel 1
