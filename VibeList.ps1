param(
    [switch]$SmokeTest,
    [string]$DataDirectory
)

if ([Environment]::GetEnvironmentVariable("VIBELIST_SMOKE_TEST") -eq "1") {
    $SmokeTest = $true
}
if ([string]::IsNullOrWhiteSpace($DataDirectory)) {
    $DataDirectory = [Environment]::GetEnvironmentVariable("VIBELIST_DATA_DIRECTORY")
}

$ErrorActionPreference = "Stop"
$script:startupTracePath = [Environment]::GetEnvironmentVariable("VIBELIST_TRACE_PATH")
function Write-StartupTrace([string]$message) {
    if ([string]::IsNullOrWhiteSpace($script:startupTracePath)) { return }
    try { "$(Get-Date -Format o) $message" | Add-Content -LiteralPath $script:startupTracePath -Encoding UTF8 }
    catch { }
}
Write-StartupTrace "start"
$script:appVersion = [Version]"1.2.5"
$defaultUpdateApiUrl = "https://api.github.com/repos/aack12-pixel/VibeList-Windows/releases/latest"
$updateApiOverride = [Environment]::GetEnvironmentVariable("VIBELIST_UPDATE_API")
$script:updateApiUrl = if (-not [string]::IsNullOrWhiteSpace($updateApiOverride) -and
    $updateApiOverride.Trim() -match '^https://api\.github\.com/repos/[^/]+/[^/]+/releases/latest$') {
    $updateApiOverride.Trim()
} else {
    $defaultUpdateApiUrl
}

$script:todoFontDirectory = [Environment]::GetEnvironmentVariable("VIBELIST_FONT_DIR")
if ([string]::IsNullOrWhiteSpace($script:todoFontDirectory)) { $script:todoFontDirectory = $PSScriptRoot }
$script:todoFontFiles = @("NanumGothic-Regular.ttf")

if (@($script:todoFontFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $script:todoFontDirectory $_)) }).Count -gt 0) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $bootstrapHeaders = @{ "User-Agent" = "VibeList/$($script:appVersion)"; "Accept" = "application/vnd.github+json" }
        $bootstrapRelease = Invoke-RestMethod -Uri $script:updateApiUrl -Headers $bootstrapHeaders -TimeoutSec 12 -UseBasicParsing
        foreach ($fontName in $script:todoFontFiles) {
            $fontDestination = Join-Path $script:todoFontDirectory $fontName
            if (Test-Path -LiteralPath $fontDestination) { continue }
            $fontAsset = @($bootstrapRelease.assets | Where-Object name -eq $fontName | Select-Object -First 1)
            if (-not $fontAsset) { continue }
            $bootstrapClient = New-Object Net.WebClient
            $bootstrapClient.Headers.Add("User-Agent", "VibeList/$($script:appVersion)")
            try { $bootstrapClient.DownloadFile([string]$fontAsset.browser_download_url, $fontDestination) }
            finally { $bootstrapClient.Dispose() }
            if ([string]$fontAsset.digest -match "^sha256:([a-fA-F0-9]{64})$" -and
                (Get-FileHash -LiteralPath $fontDestination -Algorithm SHA256).Hash -ne $Matches[1]) {
                Remove-Item -LiteralPath $fontDestination -Force -ErrorAction SilentlyContinue
            }
        }
    } catch { }
}
Write-StartupTrace "font-ready"

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;

public static class VibeListTaskbar
{
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(System.IntPtr windowHandle, int command);

    [DllImport("kernel32.dll")]
    public static extern System.IntPtr GetConsoleWindow();
}
"@
[void][VibeListTaskbar]::SetCurrentProcessExplicitAppUserModelID("VibeList.Desktop.1")
$consoleHandle = [VibeListTaskbar]::GetConsoleWindow()
if ($consoleHandle -ne [IntPtr]::Zero) {
    [void][VibeListTaskbar]::ShowWindow($consoleHandle, 0)
}
Write-StartupTrace "assemblies-ready"

Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;

public class VibeTodo : INotifyPropertyChanged
{
    private bool done;
    private string title;
    private string bucket;
    private int sortOrder;
    public string Id { get; set; }
    public string Title
    {
        get { return title; }
        set
        {
            if (title != value)
            {
                title = value;
                PropertyChangedEventHandler handler = PropertyChanged;
                if (handler != null)
                {
                    handler(this, new PropertyChangedEventArgs("Title"));
                }
            }
        }
    }
    public long CreatedAt { get; set; }
    public string Bucket
    {
        get { return bucket; }
        set
        {
            if (bucket != value)
            {
                bucket = value;
                PropertyChangedEventHandler handler = PropertyChanged;
                if (handler != null) { handler(this, new PropertyChangedEventArgs("Bucket")); }
            }
        }
    }
    public int SortOrder
    {
        get { return sortOrder; }
        set
        {
            if (sortOrder != value)
            {
                sortOrder = value;
                PropertyChangedEventHandler handler = PropertyChanged;
                if (handler != null) { handler(this, new PropertyChangedEventArgs("SortOrder")); }
            }
        }
    }
    public bool Done
    {
        get { return done; }
        set
        {
            if (done != value)
            {
                done = value;
                PropertyChangedEventHandler handler = PropertyChanged;
                if (handler != null)
                {
                    handler(this, new PropertyChangedEventArgs("Done"));
                }
            }
        }
    }
    public event PropertyChangedEventHandler PropertyChanged;
}
"@

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Vibe List" Width="460" Height="720" MinWidth="360" MinHeight="500"
        WindowStartupLocation="CenterScreen" WindowStyle="None" ResizeMode="CanResizeWithGrip" ShowInTaskbar="True"
        Background="{DynamicResource WindowBg}" Foreground="{DynamicResource PrimaryText}"
        FontFamily="{DynamicResource AppFont}" TextOptions.TextFormattingMode="Ideal">
    <Window.Resources>
        <FontFamily x:Key="AppFont">Segoe UI Variable Text, Malgun Gothic</FontFamily>
        <FontFamily x:Key="TodoFont">NanumGothic, Malgun Gothic</FontFamily>
        <SolidColorBrush x:Key="WindowBg" Color="#15101B"/>
        <SolidColorBrush x:Key="PrimaryText" Color="#FFF8F4"/>
        <SolidColorBrush x:Key="Panel" Color="#241B2D"/>
        <SolidColorBrush x:Key="RowBg" Color="#211827"/>
        <SolidColorBrush x:Key="ProgressBg" Color="#49364F"/>
        <SolidColorBrush x:Key="WindowBorder" Color="#44344F"/>
        <SolidColorBrush x:Key="Divider" Color="#57465F"/>
        <SolidColorBrush x:Key="Muted" Color="#B9ACBE"/>
        <SolidColorBrush x:Key="Subtle" Color="#817487"/>
        <SolidColorBrush x:Key="Completed" Color="#8E8194"/>
        <SolidColorBrush x:Key="FilterBg" Color="#32263C"/>
        <SolidColorBrush x:Key="HoverBg" Color="#3A2C45"/>
        <SolidColorBrush x:Key="ButtonTextDark" Color="#25121D"/>
        <SolidColorBrush x:Key="Coral" Color="#FF776D"/>
        <SolidColorBrush x:Key="CoralHover" Color="#FF968D"/>
        <SolidColorBrush x:Key="Lilac" Color="#C98CFF"/>
        <Style TargetType="Button">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Foreground" Value="{DynamicResource PrimaryText}"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="FontFamily" Value="{DynamicResource AppFont}"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
        </Style>
        <Style x:Key="FilterButton" TargetType="Button">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Foreground" Value="{DynamicResource PrimaryText}"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
            <Setter Property="Padding" Value="12,7"/>
            <Setter Property="Margin" Value="0,0,6,0"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Background" Value="{DynamicResource FilterBg}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bg" Background="{TemplateBinding Background}" CornerRadius="13" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bg" Property="Opacity" Value="0.82"/></Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="IconButton" TargetType="Button">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Foreground" Value="{DynamicResource PrimaryText}"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
            <Setter Property="Width" Value="34"/>
            <Setter Property="Height" Value="34"/>
            <Setter Property="FontSize" Value="16"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bg" Background="{TemplateBinding Background}" CornerRadius="10">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bg" Property="Background" Value="{DynamicResource HoverBg}"/></Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="TodoListItemStyle" TargetType="ListBoxItem">
            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
            <Setter Property="Padding" Value="0"/>
            <Setter Property="Margin" Value="0,0,0,8"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
            <Setter Property="Template">
                <Setter.Value><ControlTemplate TargetType="ListBoxItem"><ContentPresenter/></ControlTemplate></Setter.Value>
            </Setter>
        </Style>
        <DataTemplate x:Key="TodoItemTemplate">
            <Border x:Name="Row" Background="{DynamicResource RowBg}" CornerRadius="14" Padding="9,11">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="25"/>
                        <ColumnDefinition Width="34"/>
                        <ColumnDefinition/>
                        <ColumnDefinition Width="30"/>
                        <ColumnDefinition Width="30"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock x:Name="DragHandle" Grid.Column="0" Text="⠿" Tag="{Binding Id}" Cursor="SizeAll"
                               Foreground="{DynamicResource Subtle}" FontSize="17" FontWeight="Bold"
                               VerticalAlignment="Center" HorizontalAlignment="Center" ToolTip="잡아서 순서 바꾸기"/>
                    <CheckBox Grid.Column="1" IsChecked="{Binding Done, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}"
                              VerticalAlignment="Center" HorizontalAlignment="Center" Width="18" Height="18" Cursor="Hand"/>
                    <TextBlock Grid.Column="2" Text="{Binding Title}" VerticalAlignment="Center" FontFamily="{DynamicResource TodoFont}"
                               FontWeight="Normal" FontSize="15" TextWrapping="Wrap" Margin="7,0,8,0">
                        <TextBlock.Style>
                            <Style TargetType="TextBlock">
                                <Setter Property="Foreground" Value="{DynamicResource PrimaryText}"/>
                                <Style.Triggers>
                                    <DataTrigger Binding="{Binding Done}" Value="True">
                                        <Setter Property="Foreground" Value="{DynamicResource Completed}"/>
                                        <Setter Property="TextDecorations" Value="Strikethrough"/>
                                    </DataTrigger>
                                </Style.Triggers>
                            </Style>
                        </TextBlock.Style>
                    </TextBlock>
                    <Button x:Name="EditTodoButton" Grid.Column="3" Content="✎" Tag="{Binding Id}" FontSize="15" Foreground="{DynamicResource Lilac}" ToolTip="수정"/>
                    <Button x:Name="DeleteTodoButton" Grid.Column="4" Content="×" Tag="{Binding Id}" FontSize="17" Foreground="{DynamicResource Muted}" ToolTip="삭제"/>
                </Grid>
            </Border>
        </DataTemplate>
    </Window.Resources>

    <Border x:Name="AppRoot" Background="{DynamicResource WindowBg}" BorderBrush="{DynamicResource WindowBorder}" BorderThickness="1" CornerRadius="12">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="54"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>

            <Grid x:Name="TitleBar" Grid.Row="0" Background="Transparent">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center" Margin="18,0,0,0">
                    <Image x:Name="BrandIcon" Width="27" Height="27" Stretch="Uniform" Margin="0,0,9,0"/>
                    <TextBlock Text="VIBE LIST" FontWeight="Black" FontSize="15" VerticalAlignment="Center"/>
                    <Border Width="1" Height="13" Background="{DynamicResource Divider}" Margin="11,0"/>
                    <TextBlock Text="제작자 신대훈" Foreground="{DynamicResource Muted}" FontSize="10" VerticalAlignment="Center"/>
                </StackPanel>
                <Button x:Name="UpdateButton" Grid.Column="1" Style="{StaticResource FilterButton}" Content="↻ 확인"
                        Background="{DynamicResource Panel}" Foreground="{DynamicResource Muted}" FontSize="9.5"
                        Padding="5,3" Margin="7,0,5,0" VerticalAlignment="Center" ToolTip="업데이트 확인"/>
                <TextBlock x:Name="UpdateNoticeText" Grid.Column="2" Text="확인 중..." Foreground="{DynamicResource Muted}"
                           FontSize="9.5" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" ToolTip="업데이트 상태 확인 중"/>
                <StackPanel Grid.Column="3" Orientation="Horizontal" Margin="0,0,8,0" VerticalAlignment="Center">
                    <Button x:Name="OptionsButton" Style="{StaticResource IconButton}" Content="⚙" ToolTip="옵션"/>
                    <Button x:Name="PinButton" Style="{StaticResource IconButton}" Content="◇" ToolTip="항상 위에 표시"/>
                    <Button x:Name="MinButton" Style="{StaticResource IconButton}" Content="—" ToolTip="최소화"/>
                    <Button x:Name="CloseButton" Style="{StaticResource IconButton}" Content="×" ToolTip="닫기"/>
                </StackPanel>
            </Grid>

            <Grid Grid.Row="1" Margin="24,8,24,18">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <Grid Grid.Row="0" Margin="0,4,0,20">
                    <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="118"/></Grid.ColumnDefinitions>
                    <StackPanel>
                        <TextBlock x:Name="TodayText" Foreground="{StaticResource Muted}" FontSize="12" Margin="1,0,0,8"/>
                        <TextBlock Text="오늘 할 일," FontSize="29" FontWeight="Black"/>
                        <TextBlock Text="가볍게 끝내기." FontSize="29" FontWeight="Black" Foreground="{StaticResource Coral}"/>
                    </StackPanel>
                    <Border Grid.Column="1" Background="{DynamicResource RowBg}" CornerRadius="17" Padding="14" Margin="12,0,0,0">
                        <StackPanel VerticalAlignment="Center">
                            <TextBlock Text="오늘의 달성률" Foreground="{StaticResource Muted}" FontSize="11"/>
                            <TextBlock x:Name="ProgressText" Text="0%" FontSize="28" FontWeight="Black" Margin="0,3,0,7"/>
                            <ProgressBar x:Name="ProgressBar" Height="6" Minimum="0" Maximum="100" Value="0" Foreground="{StaticResource Coral}" Background="{DynamicResource ProgressBg}" BorderThickness="0"/>
                        </StackPanel>
                    </Border>
                </Grid>

                <Border Grid.Row="1" Background="{DynamicResource Panel}" CornerRadius="16" Padding="9" Margin="0,0,0,15">
                    <Grid>
                        <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="82"/></Grid.ColumnDefinitions>
                        <TextBox x:Name="TodoInput" Grid.Column="0" Background="Transparent" BorderThickness="0" Foreground="{DynamicResource PrimaryText}"
                                 CaretBrush="{DynamicResource Coral}" FontFamily="{DynamicResource TodoFont}" FontWeight="Normal"
                                 FontSize="15" Padding="9,9" VerticalContentAlignment="Center"
                                 ToolTip="할 일을 입력하고 Enter를 누르세요"/>
                        <Button x:Name="AddButton" Grid.Column="1" Content="+  추가" Background="{DynamicResource Coral}" Foreground="{DynamicResource ButtonTextDark}"
                                FontWeight="Bold" FontSize="13" Margin="5,0,0,0">
                            <Button.Template>
                                <ControlTemplate TargetType="Button">
                                    <Border x:Name="bg" Background="{TemplateBinding Background}" CornerRadius="12" Padding="10,9">
                                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    </Border>
                                    <ControlTemplate.Triggers>
                                        <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bg" Property="Background" Value="{DynamicResource CoralHover}"/></Trigger>
                                    </ControlTemplate.Triggers>
                                </ControlTemplate>
                            </Button.Template>
                        </Button>
                    </Grid>
                </Border>

                <Grid Grid.Row="2" Margin="0,0,0,13">
                    <StackPanel Orientation="Horizontal">
                        <Button x:Name="AllButton" Style="{StaticResource FilterButton}" Content="전체"/>
                        <Button x:Name="ActiveButton" Style="{StaticResource FilterButton}" Content="진행 중"/>
                        <Button x:Name="DoneButton" Style="{StaticResource FilterButton}" Content="완료"/>
                    </StackPanel>
                    <Button x:Name="ClearButton" Content="완료 비우기" HorizontalAlignment="Right" Foreground="{StaticResource Muted}" FontSize="11"/>
                </Grid>

                <TextBlock x:Name="CountText" Grid.Row="3" Foreground="{StaticResource Muted}" FontSize="11" Margin="2,0,0,9"/>

                <Grid Grid.Row="4">
                    <ScrollViewer x:Name="TodoScroll" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                        <StackPanel>
                            <Grid Margin="2,0,2,7">
                                <TextBlock Text="🔥  지금 할 일" FontWeight="Bold" FontSize="13" VerticalAlignment="Center"/>
                                <TextBlock x:Name="NowCountText" HorizontalAlignment="Right" Foreground="{DynamicResource Muted}" FontSize="10" VerticalAlignment="Center"/>
                            </Grid>
                            <ListBox x:Name="NowTodoList" Tag="now" AllowDrop="True" MinHeight="38" Background="Transparent" BorderThickness="0"
                                     ScrollViewer.VerticalScrollBarVisibility="Disabled" ScrollViewer.HorizontalScrollBarVisibility="Disabled"
                                     ItemContainerStyle="{StaticResource TodoListItemStyle}" ItemTemplate="{StaticResource TodoItemTemplate}"/>
                            <TextBlock x:Name="NowEmptyText" Text="지금 할 일이 없습니다. 나중 할 일을 끌어오세요." Foreground="{DynamicResource Subtle}"
                                       FontSize="11" Margin="12,8,0,14" Visibility="Collapsed"/>

                            <Grid x:Name="LaterHeader" Margin="2,7,2,7">
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="🌙  나중에 할 일" FontWeight="Bold" FontSize="13" VerticalAlignment="Center"/>
                                    <TextBlock x:Name="LaterCountText" Foreground="{DynamicResource Muted}" FontSize="10" Margin="8,1,0,0" VerticalAlignment="Center"/>
                                </StackPanel>
                                <Button x:Name="LaterToggleButton" Content="⌃" HorizontalAlignment="Right" Foreground="{DynamicResource Muted}"
                                        FontSize="14" Width="28" Height="24" ToolTip="나중에 할 일 접기/펼치기"/>
                            </Grid>
                            <ListBox x:Name="LaterTodoList" Tag="later" AllowDrop="True" MinHeight="38" Background="Transparent" BorderThickness="0"
                                     ScrollViewer.VerticalScrollBarVisibility="Disabled" ScrollViewer.HorizontalScrollBarVisibility="Disabled"
                                     ItemContainerStyle="{StaticResource TodoListItemStyle}" ItemTemplate="{StaticResource TodoItemTemplate}"/>
                            <TextBlock x:Name="LaterEmptyText" Text="당장 하지 않아도 되는 일을 여기로 끌어놓으세요." Foreground="{DynamicResource Subtle}"
                                       FontSize="11" Margin="12,8,0,8" Visibility="Collapsed"/>
                        </StackPanel>
                    </ScrollViewer>
                </Grid>

                <Grid Grid.Row="5" Margin="2,13,2,0">
                    <TextBlock x:Name="StatusText" Text="자동 저장됨" Foreground="{DynamicResource Subtle}" FontSize="10"/>
                </Grid>
            </Grid>
        </Grid>
    </Border>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
Write-StartupTrace "window-created"

if (@($script:todoFontFiles | Where-Object { Test-Path -LiteralPath (Join-Path $script:todoFontDirectory $_) }).Count -eq $script:todoFontFiles.Count) {
    try {
        $fontDirectory = $script:todoFontDirectory.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        $fontDirectoryUri = New-Object System.Uri($fontDirectory, [System.UriKind]::Absolute)
        $window.Resources["TodoFont"] = [Windows.Media.FontFamily]::new($fontDirectoryUri, "./#NanumGothic")
    } catch { }
}

$iconPath = [Environment]::GetEnvironmentVariable("VIBELIST_ICON_PATH")
if ([string]::IsNullOrWhiteSpace($iconPath)) {
    $icoPath = Join-Path $PSScriptRoot "VibeList.ico"
    $pngPath = Join-Path $PSScriptRoot "VibeList.png"
    $iconPath = if (Test-Path -LiteralPath $icoPath) { $icoPath } else { $pngPath }
}
if (Test-Path -LiteralPath $iconPath) {
    try {
        $iconUri = New-Object System.Uri($iconPath, [System.UriKind]::Absolute)
        $window.Icon = [Windows.Media.Imaging.BitmapFrame]::Create($iconUri)
    } catch { }
}

function Get-Control([string]$name) { $window.FindName($name) }

$appRoot = Get-Control "AppRoot"
$titleBar = Get-Control "TitleBar"
$brandIcon = Get-Control "BrandIcon"
$optionsButton = Get-Control "OptionsButton"
$updateButton = Get-Control "UpdateButton"
$updateNoticeText = Get-Control "UpdateNoticeText"
$pinButton = Get-Control "PinButton"
$minButton = Get-Control "MinButton"
$closeButton = Get-Control "CloseButton"
$todayText = Get-Control "TodayText"
$progressText = Get-Control "ProgressText"
$progressBar = Get-Control "ProgressBar"
$todoInput = Get-Control "TodoInput"
$addButton = Get-Control "AddButton"
$allButton = Get-Control "AllButton"
$activeButton = Get-Control "ActiveButton"
$doneButton = Get-Control "DoneButton"
$clearButton = Get-Control "ClearButton"
$countText = Get-Control "CountText"
$todoScroll = Get-Control "TodoScroll"
$nowTodoList = Get-Control "NowTodoList"
$laterTodoList = Get-Control "LaterTodoList"
$nowCountText = Get-Control "NowCountText"
$laterCountText = Get-Control "LaterCountText"
$nowEmptyText = Get-Control "NowEmptyText"
$laterEmptyText = Get-Control "LaterEmptyText"
$laterToggleButton = Get-Control "LaterToggleButton"
$statusText = Get-Control "StatusText"

if ($window.Icon) {
    $brandIcon.Source = $window.Icon
}
Write-StartupTrace "controls-ready"

$dataDir = if ([string]::IsNullOrWhiteSpace($DataDirectory)) {
    Join-Path $env:LOCALAPPDATA "VibeList"
} else {
    [System.IO.Path]::GetFullPath($DataDirectory)
}
$dataFile = Join-Path $dataDir "todos.json"
$settingsFile = Join-Path $dataDir "settings.json"
if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }
Write-StartupTrace "data-directory-ready"

$todos = New-Object 'System.Collections.ObjectModel.ObservableCollection[VibeTodo]'
$script:filter = "all"
$script:editingId = $null
$script:theme = "dark"
$script:zoom = 1.0
$script:lastUpdateCheck = $null
$script:laterCollapsed = $false
$script:draggedTodoId = $null
$script:dragStartPoint = $null

function Add-TodoObject($id, $title, $done, $createdAt, $bucket = "now", $sortOrder = -1) {
    $item = New-Object VibeTodo
    $item.Id = [string]$id
    $item.Title = [string]$title
    $item.Done = [bool]$done
    $item.CreatedAt = [long]$createdAt
    $item.Bucket = if ([string]$bucket -eq "later") { "later" } else { "now" }
    $item.SortOrder = [int]$sortOrder
    $todos.Add($item)
}

function Get-BucketTodos([string]$bucket) {
    return @($todos | Where-Object Bucket -eq $bucket | Sort-Object SortOrder, CreatedAt)
}

function Normalize-TodoOrder {
    foreach ($bucket in @("now", "later")) {
        $index = 0
        foreach ($item in @(Get-BucketTodos $bucket)) {
            $item.SortOrder = $index
            $index++
        }
    }
}

function Get-NextSortOrder([string]$bucket) {
    $items = @(Get-BucketTodos $bucket)
    if ($items.Count -eq 0) { return 0 }
    return ([int]$items[-1].SortOrder + 1)
}

function Save-Todos {
    try {
        @($todos | ForEach-Object { [pscustomobject]@{
            Id=$_.Id
            Title=$_.Title
            Done=$_.Done
            CreatedAt=$_.CreatedAt
            Bucket=$_.Bucket
            SortOrder=$_.SortOrder
        } }) |
            ConvertTo-Json -Depth 3 | Set-Content -Path $dataFile -Encoding UTF8
    } catch { }
}

function Save-Settings {
    try {
        [pscustomobject]@{
            Width=$window.Width
            Height=$window.Height
            Left=$window.Left
            Top=$window.Top
            Topmost=$window.Topmost
            Theme=$script:theme
            Zoom=$script:zoom
            LastUpdateCheck=$script:lastUpdateCheck
            LaterCollapsed=$script:laterCollapsed
        } |
            ConvertTo-Json | Set-Content -Path $settingsFile -Encoding UTF8
    } catch { }
}

function Set-FilterButtonState {
    $normal = $window.Resources["FilterBg"]
    $selected = $window.Resources["Coral"]
    $selectedText = $window.Resources["ButtonTextDark"]
    $normalText = $window.Resources["PrimaryText"]
    foreach ($pair in @(@($allButton,"all"), @($activeButton,"active"), @($doneButton,"done"))) {
        $pair[0].Background = if ($script:filter -eq $pair[1]) { $selected } else { $normal }
        $pair[0].Foreground = if ($script:filter -eq $pair[1]) { $selectedText } else { $normalText }
    }
}

function Set-BrushResource([string]$name, [string]$color) {
    $window.Resources[$name] = [Windows.Media.BrushConverter]::new().ConvertFromString($color)
}

function Apply-Theme([string]$theme) {
    if ($theme -ne "light") { $theme = "dark" }
    $script:theme = $theme

    if ($theme -eq "light") {
        $palette = @{
            WindowBg="#FFFFFF"; PrimaryText="#2B2530"; Panel="#F2ECF4"; RowBg="#F8F4FA"
            ProgressBg="#E7DDEB"; WindowBorder="#D8CEDB"; Divider="#D8CEDB"
            Muted="#756B7A"; Subtle="#8A7F8E"; Completed="#A29AA5"
            FilterBg="#EEE7F0"; HoverBg="#E6DCE9"; ButtonTextDark="#25121D"
        }
    } else {
        $palette = @{
            WindowBg="#15101B"; PrimaryText="#FFF8F4"; Panel="#241B2D"; RowBg="#211827"
            ProgressBg="#49364F"; WindowBorder="#44344F"; Divider="#57465F"
            Muted="#B9ACBE"; Subtle="#817487"; Completed="#8E8194"
            FilterBg="#32263C"; HoverBg="#3A2C45"; ButtonTextDark="#25121D"
        }
    }

    foreach ($entry in $palette.GetEnumerator()) {
        Set-BrushResource $entry.Key $entry.Value
    }

    if ($script:darkThemeMenuItem) { $script:darkThemeMenuItem.IsChecked = ($theme -eq "dark") }
    if ($script:lightThemeMenuItem) { $script:lightThemeMenuItem.IsChecked = ($theme -eq "light") }
    if ($script:optionsMenu) {
        $script:optionsMenu.Background = $window.Resources["Panel"]
        $script:optionsMenu.Foreground = $window.Resources["PrimaryText"]
    }
    Set-FilterButtonState
}

function Set-Zoom([double]$zoom, [bool]$save) {
    $zoom = [math]::Max(0.75, [math]::Min(1.40, $zoom))
    $script:zoom = [math]::Round($zoom, 2)
    $appRoot.LayoutTransform = New-Object Windows.Media.ScaleTransform($script:zoom, $script:zoom)
    $window.MinWidth = 360 * $script:zoom
    $window.MinHeight = 500 * $script:zoom
    if ($script:zoomMenuItem) {
        $script:zoomMenuItem.Header = "화면 크기: $([math]::Round($script:zoom * 100))%  (Ctrl+휠)"
    }
    if ($save) { Save-Settings }
}

function Test-UpdateConfigured {
    return [bool]($script:updateApiUrl -match '^https://api\.github\.com/repos/[^/]+/[^/]+/releases/latest$')
}

function Get-ReleaseDateText($release) {
    $rawDate = if (-not [string]::IsNullOrWhiteSpace([string]$release.published_at)) {
        [string]$release.published_at
    } else {
        [string]$release.created_at
    }
    $releaseDate = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse($rawDate, [ref]$releaseDate)) {
        return $releaseDate.ToLocalTime().ToString('yyyy-MM-dd')
    }
    return '날짜 확인 불가'
}

function Show-AppMessage([string]$message, [string]$title, [Windows.MessageBoxImage]$icon) {
    [void][Windows.MessageBox]::Show($window, $message, $title, [Windows.MessageBoxButton]::OK, $icon)
}

function Get-LatestRelease {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = @{
        "User-Agent" = "VibeList/$($script:appVersion)"
        "Accept" = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2026-03-10"
    }
    return Invoke-RestMethod -Uri $script:updateApiUrl -Headers $headers -Method Get -TimeoutSec 10 -UseBasicParsing
}

function Get-ReleaseVersion($release) {
    $tag = ([string]$release.tag_name).Trim()
    if ($tag.StartsWith("v", [StringComparison]::OrdinalIgnoreCase)) { $tag = $tag.Substring(1) }
    $version = $null
    if (-not [Version]::TryParse($tag, [ref]$version)) {
        throw "릴리스 버전 형식을 읽을 수 없습니다: $($release.tag_name)"
    }
    return $version
}

function Install-Release($release, [Version]$releaseVersion) {
    $currentExe = [Environment]::GetEnvironmentVariable("VIBELIST_EXE_PATH")
    $launcherPidText = [Environment]::GetEnvironmentVariable("VIBELIST_LAUNCHER_PID")
    $isExeMode = (-not [string]::IsNullOrWhiteSpace($currentExe)) -and (Test-Path -LiteralPath $currentExe)

    if ($isExeMode) {
        $assetName = "VibeList.exe"
        $currentFile = $currentExe
        $downloadFileName = "VibeList-$releaseVersion.exe"
        $launchMode = "Exe"
    } else {
        $assetName = "VibeList.ps1"
        $currentFile = $PSCommandPath
        $downloadFileName = "VibeList-$releaseVersion.ps1"
        $launchMode = "Script"
        $launcherPidText = $PID.ToString()
    }

    $asset = @($release.assets | Where-Object name -eq $assetName | Select-Object -First 1)
    if (-not $asset) { throw "릴리스에 $assetName 파일이 없습니다." }

    $updateDir = Join-Path $dataDir "updates"
    if (-not (Test-Path -LiteralPath $updateDir)) { New-Item -ItemType Directory -Path $updateDir -Force | Out-Null }
    $downloadPath = Join-Path $updateDir $downloadFileName

    $statusText.Text = "업데이트 다운로드 중..."
    $client = New-Object Net.WebClient
    $client.Headers.Add("User-Agent", "VibeList/$($script:appVersion)")
    try {
        $client.DownloadFile([string]$asset.browser_download_url, $downloadPath)
    } finally {
        $client.Dispose()
    }

    $expectedHash = $null
    if ([string]$asset.digest -match "^sha256:([a-fA-F0-9]{64})$") {
        $expectedHash = $Matches[1]
    } else {
        $hashAssetName = "$assetName.sha256"
        $hashAsset = @($release.assets | Where-Object name -eq $hashAssetName | Select-Object -First 1)
        if ($hashAsset) {
            $hashClient = New-Object Net.WebClient
            $hashClient.Headers.Add("User-Agent", "VibeList/$($script:appVersion)")
            try {
                $hashText = $hashClient.DownloadString([string]$hashAsset.browser_download_url)
            } finally {
                $hashClient.Dispose()
            }
            if ($hashText -match "([a-fA-F0-9]{64})") { $expectedHash = $Matches[1] }
        }
    }
    if ([string]::IsNullOrWhiteSpace($expectedHash)) {
        Remove-Item -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue
        throw "업데이트 파일의 SHA-256 검증 정보를 찾을 수 없습니다."
    }

    $actualHash = (Get-FileHash -LiteralPath $downloadPath -Algorithm SHA256).Hash
    if ($actualHash -ne $expectedHash) {
        Remove-Item -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue
        throw "업데이트 파일 검증에 실패했습니다. 설치하지 않았습니다."
    }

    if ($launchMode -eq "Script") {
        foreach ($fontName in @("NanumGothic-Regular.ttf")) {
            $fontAsset = @($release.assets | Where-Object name -eq $fontName | Select-Object -First 1)
            if (-not $fontAsset) { continue }
            $fontDestination = Join-Path (Split-Path -Parent $currentFile) $fontName
            $fontClient = New-Object Net.WebClient
            $fontClient.Headers.Add("User-Agent", "VibeList/$($script:appVersion)")
            try {
                $fontClient.DownloadFile([string]$fontAsset.browser_download_url, $fontDestination)
            } finally {
                $fontClient.Dispose()
            }
            if ([string]$fontAsset.digest -match "^sha256:([a-fA-F0-9]{64})$") {
                $fontHash = (Get-FileHash -LiteralPath $fontDestination -Algorithm SHA256).Hash
                if ($fontHash -ne $Matches[1]) {
                    Remove-Item -LiteralPath $fontDestination -Force -ErrorAction SilentlyContinue
                    throw "글꼴 파일 검증에 실패했습니다."
                }
            }
        }
    }

    $applyScript = Join-Path $updateDir "apply-update.ps1"
    @'
param([string]$CurrentFile, [string]$NewFile, [string]$LaunchMode, [int]$WaitForPid, [string]$ErrorLog)
$ErrorActionPreference = "Stop"
try {
    if ($WaitForPid -gt 0) { Wait-Process -Id $WaitForPid -ErrorAction SilentlyContinue }
    $copied = $false
    for ($attempt = 0; $attempt -lt 20 -and -not $copied; $attempt++) {
        try {
            Copy-Item -LiteralPath $NewFile -Destination $CurrentFile -Force
            $copied = $true
        } catch {
            Start-Sleep -Milliseconds 250
        }
    }
    if (-not $copied) { throw "업데이트 파일을 교체할 수 없습니다." }
    if ($LaunchMode -eq "Script") {
        $windowlessLauncher = Join-Path (Split-Path -Parent $CurrentFile) "VibeList.vbs"
        if (Test-Path -LiteralPath $windowlessLauncher) {
            Start-Process -FilePath "wscript.exe" -ArgumentList "`"$windowlessLauncher`""
        } else {
            $args = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$CurrentFile`""
            Start-Process -FilePath "powershell.exe" -ArgumentList $args -WindowStyle Hidden
        }
    } else {
        Start-Process -FilePath $CurrentFile
    }
} catch {
    $_ | Out-String | Set-Content -LiteralPath $ErrorLog -Encoding UTF8
}
'@ | Set-Content -LiteralPath $applyScript -Encoding UTF8

    $launcherPid = 0
    [void][int]::TryParse($launcherPidText, [ref]$launcherPid)
    $errorLog = Join-Path $dataDir "update-error.log"
    $arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$applyScript`" -CurrentFile `"$currentFile`" -NewFile `"$downloadPath`" -LaunchMode $launchMode -WaitForPid $launcherPid -ErrorLog `"$errorLog`""
    Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -WindowStyle Hidden
    $window.Close()
}

function Complete-UpdateFailure([string]$message, [bool]$manual) {
    Write-StartupTrace "update-failed message=$message"
    $updateNoticeText.Text = "확인 실패 · 다시 눌러주세요"
    $updateNoticeText.ToolTip = "업데이트 확인 실패 · 다시 눌러주세요"
    $updateNoticeText.Foreground = $window.Resources["Coral"]
    $updateButton.Content = "↻ 확인"
    $updateButton.IsEnabled = $true
    $statusText.Text = "자동 저장됨"
    if ($manual) { Show-AppMessage "업데이트를 확인하지 못했습니다.`n`n$message" "업데이트" ([Windows.MessageBoxImage]::Warning) }
}

function Complete-UpdateCheck($release, [bool]$manual, [bool]$allowInstallPrompt) {
    try {
        $releaseVersion = Get-ReleaseVersion $release
        $releaseDate = Get-ReleaseDateText $release
        Write-StartupTrace "update-release version=$releaseVersion date=$releaseDate"
        $script:lastUpdateCheck = [DateTimeOffset]::Now.ToString("o")
        Save-Settings

        if ($releaseVersion -le $script:appVersion) {
            $updateNoticeText.Text = "현재 최신 · $releaseDate"
            $updateNoticeText.ToolTip = "현재 최신 버전입니다 · 최신 배포 $releaseDate · v$releaseVersion"
            $updateNoticeText.Foreground = $window.Resources["Muted"]
            $updateButton.Content = "↻ 확인"
            if ($manual) { Show-AppMessage "현재 최신 버전입니다.  v$($script:appVersion)" "업데이트" ([Windows.MessageBoxImage]::Information) }
            return
        }

        $updateNoticeText.Text = "업데이트 있음 · $releaseDate"
        $updateNoticeText.ToolTip = "최신 업데이트가 있습니다 · $releaseDate · v$releaseVersion"
        $updateNoticeText.Foreground = $window.Resources["Coral"]
        $updateButton.Content = "↓ 받기"
        if (-not $allowInstallPrompt) { return }

        $answer = [Windows.MessageBox]::Show(
            $window,
            "새 버전 v$releaseVersion 이 있습니다.`n`n지금 업데이트할까요?`n체크리스트는 그대로 유지됩니다.",
            "Vibe List 업데이트",
            [Windows.MessageBoxButton]::YesNo,
            [Windows.MessageBoxImage]::Information
        )
        if ($answer -eq [Windows.MessageBoxResult]::Yes) { Install-Release $release $releaseVersion }
    } catch {
        Complete-UpdateFailure $_.Exception.Message $manual
    } finally {
        $updateButton.IsEnabled = $true
        $statusText.Text = "자동 저장됨"
    }
}

function Check-ForUpdate([bool]$manual, [bool]$allowInstallPrompt = $true) {
    $configured = Test-UpdateConfigured
    Write-StartupTrace "update-check configured=$configured url=$script:updateApiUrl"
    if (-not $configured) {
        Complete-UpdateFailure "업데이트 주소를 확인하지 못했습니다." $manual
        return
    }
    if ($script:updatePollTimer -and $script:updatePollTimer.IsEnabled) { return }

    $statusText.Text = "업데이트 확인 중..."
    $updateButton.IsEnabled = $false
    $updateButton.Content = "확인 중"
    $updateNoticeText.Text = "최신 버전 확인 중..."
    $updateNoticeText.ToolTip = "GitHub에서 최신 버전을 확인하고 있습니다"
    $updateNoticeText.Foreground = $window.Resources["Muted"]
    $script:updateCheckManual = $manual
    $script:updateCheckAllowPrompt = $allowInstallPrompt
    $script:updateCheckStartedAt = [DateTimeOffset]::Now
    $script:updateClient = New-Object Net.WebClient
    $script:updateClient.Headers.Add("User-Agent", "VibeList/$($script:appVersion)")
    $script:updateClient.Headers.Add("Accept", "application/vnd.github+json")

    try {
        $script:updateTask = $script:updateClient.DownloadStringTaskAsync([Uri]$script:updateApiUrl)
    } catch {
        $script:updateClient.Dispose()
        Complete-UpdateFailure $_.Exception.Message $manual
        return
    }

    $script:updatePollTimer = New-Object Windows.Threading.DispatcherTimer
    $script:updatePollTimer.Interval = [TimeSpan]::FromMilliseconds(200)
    $script:updatePollTimer.Add_Tick({
        $elapsed = ([DateTimeOffset]::Now - $script:updateCheckStartedAt).TotalSeconds
        if (-not $script:updateTask.IsCompleted -and $elapsed -lt 12) { return }

        $script:updatePollTimer.Stop()
        if (-not $script:updateTask.IsCompleted) {
            try { $script:updateClient.CancelAsync() } catch { }
            $script:updateClient.Dispose()
            Complete-UpdateFailure "GitHub 응답 시간이 초과되었습니다." $script:updateCheckManual
            return
        }

        try {
            $json = $script:updateTask.GetAwaiter().GetResult()
            $release = $json | ConvertFrom-Json
            $script:updateClient.Dispose()
            Complete-UpdateCheck $release $script:updateCheckManual $script:updateCheckAllowPrompt
        } catch {
            $script:updateClient.Dispose()
            Complete-UpdateFailure $_.Exception.Message $script:updateCheckManual
        }
    })
    $script:updatePollTimer.Start()
}

function Save-WindowPreview([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return }
    $window.UpdateLayout()
    $width = [math]::Max(1, [int][math]::Ceiling($window.ActualWidth))
    $height = [math]::Max(1, [int][math]::Ceiling($window.ActualHeight))
    $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap($width, $height, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($window)
    $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [IO.File]::Open($path, [IO.FileMode]::Create)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
}

$script:optionsMenu = New-Object Windows.Controls.ContextMenu
$themeMenuItem = New-Object Windows.Controls.MenuItem
$themeMenuItem.Header = "배경 색상"
$script:darkThemeMenuItem = New-Object Windows.Controls.MenuItem
$script:darkThemeMenuItem.Header = "다크"
$script:darkThemeMenuItem.IsCheckable = $true
$script:lightThemeMenuItem = New-Object Windows.Controls.MenuItem
$script:lightThemeMenuItem.Header = "화이트"
$script:lightThemeMenuItem.IsCheckable = $true
[void]$themeMenuItem.Items.Add($script:darkThemeMenuItem)
[void]$themeMenuItem.Items.Add($script:lightThemeMenuItem)
$script:zoomMenuItem = New-Object Windows.Controls.MenuItem
$script:zoomMenuItem.Header = "화면 크기: 100%  (Ctrl+휠)"
$zoomResetMenuItem = New-Object Windows.Controls.MenuItem
$zoomResetMenuItem.Header = "화면 크기 초기화"
$versionMenuItem = New-Object Windows.Controls.MenuItem
$versionMenuItem.Header = "Vibe List  v$($script:appVersion)"
$versionMenuItem.IsEnabled = $false
[void]$script:optionsMenu.Items.Add($themeMenuItem)
[void]$script:optionsMenu.Items.Add($script:zoomMenuItem)
[void]$script:optionsMenu.Items.Add($zoomResetMenuItem)
[void]$script:optionsMenu.Items.Add((New-Object Windows.Controls.Separator))
[void]$script:optionsMenu.Items.Add($versionMenuItem)
$optionsButton.ContextMenu = $script:optionsMenu

$script:darkThemeMenuItem.Add_Click({ Apply-Theme "dark"; Save-Settings })
$script:lightThemeMenuItem.Add_Click({ Apply-Theme "light"; Save-Settings })
$zoomResetMenuItem.Add_Click({ Set-Zoom 1.0 $true })
$updateButton.Add_Click({ Check-ForUpdate $true $true })
$optionsButton.Add_Click({ $script:optionsMenu.PlacementTarget = $optionsButton; $script:optionsMenu.IsOpen = $true })

function Refresh-View {
    $visible = @($todos | Where-Object {
        ($script:filter -eq "all") -or
        ($script:filter -eq "active" -and -not $_.Done) -or
        ($script:filter -eq "done" -and $_.Done)
    })
    $nowVisible = @($visible | Where-Object Bucket -eq "now" | Sort-Object SortOrder, CreatedAt)
    $laterVisible = @($visible | Where-Object Bucket -eq "later" | Sort-Object SortOrder, CreatedAt)
    $nowTodoList.ItemsSource = $nowVisible
    $laterTodoList.ItemsSource = $laterVisible
    $nowCountText.Text = "$($nowVisible.Count)개"
    $laterCountText.Text = "$($laterVisible.Count)개"
    $nowEmptyText.Visibility = if ($nowVisible.Count -eq 0) { "Visible" } else { "Collapsed" }
    $laterTodoList.Visibility = if ($script:laterCollapsed) { "Collapsed" } else { "Visible" }
    $laterEmptyText.Visibility = if (-not $script:laterCollapsed -and $laterVisible.Count -eq 0) { "Visible" } else { "Collapsed" }
    $laterToggleButton.Content = if ($script:laterCollapsed) { "⌄" } else { "⌃" }
    $doneCount = @($todos | Where-Object Done).Count
    $activeCount = $todos.Count - $doneCount
    $percent = if ($todos.Count -gt 0) { [math]::Round(($doneCount / $todos.Count) * 100) } else { 0 }
    $progressBar.Value = $percent
    $progressText.Text = "$percent%"
    $countText.Text = "남은 할 일 $activeCount개  ·  완료 $doneCount개"
    $clearButton.Visibility = if ($doneCount -gt 0) { "Visible" } else { "Collapsed" }
    Set-FilterButtonState
}

function Move-Todo([string]$todoId, [string]$destinationBucket, [string]$targetId, [bool]$insertAfter) {
    $moved = $todos | Where-Object Id -eq $todoId | Select-Object -First 1
    if (-not $moved) { return }
    if ($destinationBucket -notin @("now", "later")) { return }
    if (-not [string]::IsNullOrWhiteSpace($targetId) -and $targetId -eq $todoId -and $moved.Bucket -eq $destinationBucket) { return }

    $destination = New-Object 'System.Collections.Generic.List[VibeTodo]'
    foreach ($item in @(Get-BucketTodos $destinationBucket)) {
        if ($item.Id -ne $todoId) { $destination.Add($item) }
    }

    $insertIndex = $destination.Count
    if (-not [string]::IsNullOrWhiteSpace($targetId)) {
        for ($index = 0; $index -lt $destination.Count; $index++) {
            if ($destination[$index].Id -eq $targetId) {
                $insertIndex = $index + $(if ($insertAfter) { 1 } else { 0 })
                break
            }
        }
    }

    $moved.Bucket = $destinationBucket
    $destination.Insert($insertIndex, $moved)
    for ($index = 0; $index -lt $destination.Count; $index++) {
        $destination[$index].Bucket = $destinationBucket
        $destination[$index].SortOrder = $index
    }
    Normalize-TodoOrder
    Save-Todos
    Refresh-View
}

function Get-TodoItemContainer($list, $source) {
    if (-not $source) { return $null }
    try { return [Windows.Controls.ItemsControl]::ContainerFromElement($list, $source) }
    catch { return $null }
}

function Clear-EditState {
    $script:editingId = $null
    $todoInput.Clear()
    $addButton.Content = "+  추가"
    $todoInput.ToolTip = "할 일을 입력하고 Enter를 누르세요"
}

function Begin-EditTodo($item) {
    if (-not $item) { return }
    $script:editingId = [string]$item.Id
    $todoInput.Text = [string]$item.Title
    $addButton.Content = "✓  저장"
    $todoInput.ToolTip = "내용을 고친 뒤 Enter 또는 저장을 누르세요. Esc를 누르면 취소됩니다."
    $todoInput.Focus()
    $todoInput.SelectAll()
}

function Add-NewTodo {
    $text = $todoInput.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return }

    if (-not [string]::IsNullOrWhiteSpace($script:editingId)) {
        $target = $todos | Where-Object Id -eq $script:editingId | Select-Object -First 1
        if ($target) {
            $target.Title = $text
            Save-Todos
            Clear-EditState
            Refresh-View
            return
        }
        Clear-EditState
    }

    Add-TodoObject ([guid]::NewGuid().ToString()) $text $false ([DateTimeOffset]::Now.ToUnixTimeMilliseconds()) "now" (Get-NextSortOrder "now")
    Clear-EditState
    $script:filter = "all"
    Save-Todos
    Refresh-View
}

if (Test-Path $dataFile) {
    try {
        $saved = Get-Content -Path $dataFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $loadIndex = 0
        @($saved) | ForEach-Object {
            $savedBucket = if ([string]$_.Bucket -eq "later") { "later" } else { "now" }
            $savedOrder = if ($null -ne $_.PSObject.Properties["SortOrder"]) { [int]$_.SortOrder } else { $loadIndex }
            Add-TodoObject $_.Id $_.Title $_.Done $_.CreatedAt $savedBucket $savedOrder
            $loadIndex++
        }
        Normalize-TodoOrder
    } catch { }
} else {
    Add-TodoObject ([guid]::NewGuid().ToString()) "오늘 가장 중요한 일 끝내기" $false 1 "now" 0
    Add-TodoObject ([guid]::NewGuid().ToString()) "내일 할 일 3개만 미리 적기" $false 2 "later" 0
    Save-Todos
}

if (Test-Path $settingsFile) {
    try {
        $settings = Get-Content -Path $settingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($settings.Width -ge $window.MinWidth) { $window.Width = $settings.Width }
        if ($settings.Height -ge $window.MinHeight) { $window.Height = $settings.Height }
        if ($settings.Left -ge 0) { $window.Left = $settings.Left }
        if ($settings.Top -ge 0) { $window.Top = $settings.Top }
        $window.Topmost = [bool]$settings.Topmost
        if ([string]$settings.Theme -eq "light") { $script:theme = "light" }
        if ($settings.Zoom -ge 0.75 -and $settings.Zoom -le 1.40) { $script:zoom = [double]$settings.Zoom }
        if (-not [string]::IsNullOrWhiteSpace([string]$settings.LastUpdateCheck)) {
            $script:lastUpdateCheck = [string]$settings.LastUpdateCheck
        }
        if ($null -ne $settings.PSObject.Properties["LaterCollapsed"]) {
            $script:laterCollapsed = [bool]$settings.LaterCollapsed
        }
    } catch { }
}
Write-StartupTrace "data-loaded"

Apply-Theme $script:theme
Set-Zoom $script:zoom $false

$todayText.Text = (Get-Date).ToString("M월 d일 dddd", [Globalization.CultureInfo]::GetCultureInfo("ko-KR"))
$pinButton.Content = if ($window.Topmost) { "◆" } else { "◇" }

$titleBar.Add_MouseLeftButtonDown({
    if ($_.ClickCount -eq 2) {
        $window.WindowState = if ($window.WindowState -eq "Maximized") { "Normal" } else { "Maximized" }
    } else { $window.DragMove() }
})
$pinButton.Add_Click({
    $window.Topmost = -not $window.Topmost
    $pinButton.Content = if ($window.Topmost) { "◆" } else { "◇" }
    Save-Settings
})
$minButton.Add_Click({ $window.WindowState = "Minimized" })
$closeButton.Add_Click({ $window.Close() })
$window.Add_PreviewMouseWheel({
    if (([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control) -ne 0) {
        $step = if ($_.Delta -gt 0) { 0.10 } else { -0.10 }
        Set-Zoom ($script:zoom + $step) $true
        $_.Handled = $true
    }
})
$addButton.Add_Click({ Add-NewTodo })
$todoInput.Add_KeyDown({
    if ($_.Key -eq "Enter") {
        Add-NewTodo
        $_.Handled = $true
    } elseif ($_.Key -eq "Escape" -and -not [string]::IsNullOrWhiteSpace($script:editingId)) {
        Clear-EditState
        $_.Handled = $true
    }
})
$allButton.Add_Click({ $script:filter = "all"; Refresh-View })
$activeButton.Add_Click({ $script:filter = "active"; Refresh-View })
$doneButton.Add_Click({ $script:filter = "done"; Refresh-View })
$clearButton.Add_Click({
    @($todos | Where-Object Done) | ForEach-Object { [void]$todos.Remove($_) }
    Normalize-TodoOrder
    Save-Todos
    Refresh-View
})
$laterToggleButton.Add_Click({
    $script:laterCollapsed = -not $script:laterCollapsed
    Save-Settings
    Refresh-View
})

$todoClickHandler = [Windows.RoutedEventHandler]{
    param($sender, $eventArgs)
    $source = $eventArgs.OriginalSource
    if ($source -is [Windows.Controls.CheckBox]) {
        Save-Todos
        $window.Dispatcher.BeginInvoke([Action]{ Refresh-View }, [Windows.Threading.DispatcherPriority]::Background) | Out-Null
    } elseif ($source -is [Windows.Controls.Button] -and $source.Tag) {
        $target = $todos | Where-Object Id -eq ([string]$source.Tag) | Select-Object -First 1
        if ($source.Name -eq "EditTodoButton") {
            Begin-EditTodo $target
        } elseif ($source.Name -eq "DeleteTodoButton" -and $target) {
            if ($script:editingId -eq [string]$target.Id) { Clear-EditState }
            [void]$todos.Remove($target)
            Normalize-TodoOrder
            Save-Todos
            Refresh-View
        }
    }
}

$dragMouseDownHandler = [Windows.Input.MouseButtonEventHandler]{
    param($sender, $eventArgs)
    $source = $eventArgs.OriginalSource
    if ($source -is [Windows.Controls.TextBlock] -and $source.Name -eq "DragHandle" -and $source.Tag) {
        $script:draggedTodoId = [string]$source.Tag
        $script:dragStartPoint = $eventArgs.GetPosition($window)
        $eventArgs.Handled = $true
    } else {
        $script:draggedTodoId = $null
        $script:dragStartPoint = $null
    }
}

$dragMouseMoveHandler = [Windows.Input.MouseEventHandler]{
    param($sender, $eventArgs)
    if ([string]::IsNullOrWhiteSpace($script:draggedTodoId) -or
        $null -eq $script:dragStartPoint -or
        $eventArgs.LeftButton -ne [Windows.Input.MouseButtonState]::Pressed) { return }
    $point = $eventArgs.GetPosition($window)
    if ([math]::Abs($point.X - $script:dragStartPoint.X) -lt [Windows.SystemParameters]::MinimumHorizontalDragDistance -and
        [math]::Abs($point.Y - $script:dragStartPoint.Y) -lt [Windows.SystemParameters]::MinimumVerticalDragDistance) { return }
    $data = New-Object Windows.DataObject
    $data.SetData("VibeListTodoId", $script:draggedTodoId)
    [void][Windows.DragDrop]::DoDragDrop($sender, $data, [Windows.DragDropEffects]::Move)
    $script:draggedTodoId = $null
    $script:dragStartPoint = $null
}

$dragOverHandler = [Windows.DragEventHandler]{
    param($sender, $eventArgs)
    if ($eventArgs.Data.GetDataPresent("VibeListTodoId")) {
        $eventArgs.Effects = [Windows.DragDropEffects]::Move
        $eventArgs.Handled = $true
    }
}

$dropHandler = [Windows.DragEventHandler]{
    param($sender, $eventArgs)
    if (-not $eventArgs.Data.GetDataPresent("VibeListTodoId")) { return }
    $todoId = [string]$eventArgs.Data.GetData("VibeListTodoId")
    $destinationBucket = [string]$sender.Tag
    $container = Get-TodoItemContainer $sender $eventArgs.OriginalSource
    $targetId = $null
    $insertAfter = $false
    if ($container -is [Windows.Controls.ListBoxItem] -and $container.DataContext) {
        $targetId = [string]$container.DataContext.Id
        $insertAfter = ($eventArgs.GetPosition($container).Y -gt ($container.ActualHeight / 2))
    }
    Move-Todo $todoId $destinationBucket $targetId $insertAfter
    $script:draggedTodoId = $null
    $script:dragStartPoint = $null
    $eventArgs.Handled = $true
}

foreach ($list in @($nowTodoList, $laterTodoList)) {
    $list.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, $todoClickHandler)
    $list.Add_PreviewMouseLeftButtonDown($dragMouseDownHandler)
    $list.Add_PreviewMouseMove($dragMouseMoveHandler)
    $list.Add_DragOver($dragOverHandler)
    $list.Add_Drop($dropHandler)
}
$window.Add_Closing({ Save-Todos; Save-Settings })
$window.Add_SourceInitialized({
    try {
        $windowHandle = [Windows.Interop.WindowInteropHelper]::new($window).Handle
        if ($windowHandle -ne [IntPtr]::Zero) { [void][VibeListTaskbar]::ShowWindow($windowHandle, 5) }
    } catch { }
})
$window.Add_ContentRendered({
    Write-StartupTrace "content-rendered"
    Refresh-View
    $todoInput.Focus()
    $previewPath = [Environment]::GetEnvironmentVariable("VIBELIST_SCREENSHOT_PATH")
    if (-not [string]::IsNullOrWhiteSpace($previewPath)) { Save-WindowPreview $previewPath }
    if ($SmokeTest) {
        Write-StartupTrace "smoke-close"
        $window.Dispatcher.BeginInvoke([Action]{ $window.Close() }) | Out-Null
    } elseif (Test-UpdateConfigured) {
        $script:shouldPromptForUpdate = $true
        $lastCheck = [DateTimeOffset]::MinValue
        if ([DateTimeOffset]::TryParse([string]$script:lastUpdateCheck, [ref]$lastCheck)) {
            $script:shouldPromptForUpdate = (([DateTimeOffset]::Now - $lastCheck).TotalHours -ge 24)
        }
        $script:updateTimer = New-Object Windows.Threading.DispatcherTimer
        $script:updateTimer.Interval = [TimeSpan]::FromSeconds(1)
        $script:updateTimer.Add_Tick({
            $script:updateTimer.Stop()
            Check-ForUpdate $false $script:shouldPromptForUpdate
        })
        $script:updateTimer.Start()
    }
})

Write-StartupTrace "show-dialog"
[void]$window.ShowDialog()
Write-StartupTrace "dialog-closed"
