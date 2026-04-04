Dim mode, filePath, cmd, ps1, fso
Set objShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
ps1 = fso.BuildPath(fso.GetParentFolderName(fso.GetParentFolderName(WScript.ScriptFullName)), fso.GetBaseName(WScript.ScriptFullName) & ".ps1")
mode = "" : filePath = ""
If WScript.Arguments.Count >= 1 Then mode = WScript.Arguments(0)
If WScript.Arguments.Count >= 2 Then filePath = WScript.Arguments(1)
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File " & Chr(34) & ps1 & Chr(34) & " " & Chr(34) & mode & Chr(34) & " " & Chr(34) & filePath & Chr(34)
objShell.Run cmd, 0, False