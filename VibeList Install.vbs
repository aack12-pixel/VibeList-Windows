Option Explicit

Dim shell, fileSystem, packageDirectory, sourceDirectory
Dim dataDirectory, installDirectory, desktopDirectory, shortcutPath
Dim files, fileName, sourcePath, destinationPath, shortcut, quote, launchCommand, quietInstall

Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

packageDirectory = fileSystem.GetParentFolderName(WScript.ScriptFullName)
sourceDirectory = fileSystem.BuildPath(packageDirectory, "VibeList")
dataDirectory = shell.ExpandEnvironmentStrings("%VIBELIST_INSTALL_ROOT%")
If dataDirectory = "%VIBELIST_INSTALL_ROOT%" Or Len(dataDirectory) = 0 Then
    dataDirectory = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\VibeList"
End If
installDirectory = fileSystem.BuildPath(dataDirectory, "App")

EnsureFolder dataDirectory
EnsureFolder installDirectory

files = Array( _
    "VibeList.ps1", _
    "VibeList.vbs", _
    "VibeList.ico", _
    "NanumGothic-Regular.ttf", _
    "OFL-NanumGothic.txt" _
)

For Each fileName In files
    sourcePath = fileSystem.BuildPath(sourceDirectory, fileName)
    destinationPath = fileSystem.BuildPath(installDirectory, fileName)
    If Not fileSystem.FileExists(sourcePath) Then
        MsgBox "A required Vibe List file is missing:" & vbCrLf & sourcePath, vbCritical, "Vibe List"
        WScript.Quit 1
    End If

    If LCase(fileName) = "nanumgothic-regular.ttf" And fileSystem.FileExists(destinationPath) Then
        ' Keep the installed font while the running app may have it open.
    Else
        On Error Resume Next
        fileSystem.CopyFile sourcePath, destinationPath, True
        If Err.Number <> 0 Then
            Dim copyError
            copyError = Err.Description
            Err.Clear
            On Error GoTo 0
            MsgBox "Vibe List could not be installed:" & vbCrLf & copyError, vbCritical, "Vibe List"
            WScript.Quit 1
        End If
        On Error GoTo 0
    End If
Next

desktopDirectory = shell.ExpandEnvironmentStrings("%VIBELIST_DESKTOP_DIR%")
If desktopDirectory = "%VIBELIST_DESKTOP_DIR%" Or Len(desktopDirectory) = 0 Then
    desktopDirectory = shell.SpecialFolders("Desktop")
End If
EnsureFolder desktopDirectory
shortcutPath = fileSystem.BuildPath(desktopDirectory, "VibeList.lnk")
Set shortcut = shell.CreateShortcut(shortcutPath)
shortcut.TargetPath = shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\wscript.exe"
shortcut.Arguments = Chr(34) & fileSystem.BuildPath(installDirectory, "VibeList.vbs") & Chr(34)
shortcut.WorkingDirectory = installDirectory
shortcut.IconLocation = fileSystem.BuildPath(installDirectory, "VibeList.ico") & ",0"
shortcut.WindowStyle = 1
shortcut.Description = "Vibe List"
shortcut.Save

quote = Chr(34)
launchCommand = quote & shortcut.TargetPath & quote & " " & shortcut.Arguments
shell.Run launchCommand, 0, False

quietInstall = shell.ExpandEnvironmentStrings("%VIBELIST_QUIET_INSTALL%")
If quietInstall <> "1" Then
    MsgBox "Vibe List installation/update is complete." & vbCrLf & _
           "Your existing Todo data was preserved." & vbCrLf & _
           "Use the VibeList shortcut on the Desktop.", vbInformation, "Vibe List"
End If

Sub EnsureFolder(path)
    Dim parent
    If fileSystem.FolderExists(path) Then Exit Sub
    parent = fileSystem.GetParentFolderName(path)
    If Len(parent) > 0 And Not fileSystem.FolderExists(parent) Then EnsureFolder parent
    fileSystem.CreateFolder path
End Sub
