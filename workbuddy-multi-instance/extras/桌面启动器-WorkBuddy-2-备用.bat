@echo off
echo 正在以 wb2 身份启动 WorkBuddy...
echo 注意：输入密码时屏幕不会显示任何字符，属正常现象，盲打完直接回车。
runas /savecred /user:wb2 "Z:\软件\software\workbuddy\WorkBuddy.exe"
echo.
pause