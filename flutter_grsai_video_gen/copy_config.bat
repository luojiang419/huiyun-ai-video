@echo off
if exist "E:\data\app\AI\config.json" (
    xcopy /Y "E:\data\app\AI\config.json" "build\windows\x64\runner\Release\data\"
)
