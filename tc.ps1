<#
.SYNOPSIS
    Enterprise Terms and Conditions Acceptance System
.DESCRIPTION
    Intune-compatible deployment script that creates a scheduled task for mandatory terms acceptance.
    Features centralized configuration, enhanced error handling, and comprehensive logging.
.PARAMETER Uninstall
    Removes the scheduled task and associated files
.PARAMETER LogPath
    Path for log file (default: C:\ProgramData\TermsAcceptance.log)
.PARAMETER Force
    Forces recreation of task even if terms are already accepted
.VERSION
    3.3.0
.NOTES
    Enhanced version with improved maintainability, error handling, and user experience
.EXAMPLE
    Deploy-TermsAcceptance.ps1
    Deploy-TermsAcceptance.ps1 -Uninstall
    Deploy-TermsAcceptance.ps1 -Force -LogPath "C:\Logs\CustomTerms.log"
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$Uninstall,
    [switch]$Force,
    [ValidateScript({
        $parent = Split-Path $_ -Parent
        if (-not (Test-Path $parent)) {
            throw "Parent directory does not exist: $parent"
        }
        $true
    })]
    [string]$LogPath = "C:\ProgramData\TermsAcceptance.log"
)

#region Configuration
$Config = @{
    # Core Settings
    ScriptVersion = "3.3.0"
    TaskName      = "AcceptTermsAndConditions"
    CompanyName   = "Provincial Treasury"
    TermsVersion  = "3.3.0"
    
    # File Paths
    ScriptFile    = "C:\ProgramData\TermsAcceptancePrompt.ps1"
    
    # Contact Information
    ContactNumber = "88 1110"
    ContactEmail  = "security@treasury.gov.za"
    
    # UI Settings
    FormTitle     = "Mandatory Security Terms - Provincial Treasury"
    FormSize      = @{Width = 800; Height = 650}
    
    # Registry Configuration
    RegistryPath  = "HKLM:\SOFTWARE\Provincial Treasury\TermsAcceptance"
    
    # Behavior Settings
    MaxDismissals = 3  # How many times user can dismiss before forcing acceptance
    ReminderHours = 24 # Hours between reminders after dismissal
}
#endregion

#region Logging Functions
function Write-Log {
    <#
    .SYNOPSIS
        Enhanced logging function with multiple output streams
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'DEBUG', 'SUCCESS')]
        [string]$Level = 'INFO',
        
        [switch]$NoConsole
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $caller = (Get-PSCallStack)[1].FunctionName
    $entry = "[$timestamp] [$Level] [$caller] $Message"
    
    try {
        # Ensure log directory exists
        $logDir = Split-Path $LogPath -Parent
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        
        # Write to log file
        Add-Content -Path $LogPath -Value $entry -Encoding UTF8 -ErrorAction Stop
        
        # Console output based on level
        if (-not $NoConsole) {
            switch ($Level) {
                'ERROR'   { Write-Error $Message }
                'WARNING' { Write-Warning $Message }
                'SUCCESS' { Write-Host $Message -ForegroundColor Green }
                'DEBUG'   { Write-Debug $Message }
                default   { Write-Verbose $Message -Verbose }
            }
        }
    }
    catch {
        Write-Warning "Failed to write log: $($_.Exception.Message)"
    }
}

function Start-LogSession {
    Write-Log "=== Terms Acceptance Script Started ===" -Level 'INFO'
    Write-Log "Version: $($Config.ScriptVersion)" -Level 'INFO'
    Write-Log "Computer: $env:COMPUTERNAME" -Level 'INFO'
    Write-Log "User Context: $env:USERDOMAIN\$env:USERNAME" -Level 'INFO'
    Write-Log "PowerShell Version: $($PSVersionTable.PSVersion)" -Level 'INFO'
}
#endregion

#region Registry Management
function Set-TermsAcceptance {
    <#
    .SYNOPSIS
        Records terms acceptance in registry with comprehensive metadata
    #>
    [CmdletBinding()]
    param()
    
    try {
        Write-Log "Recording terms acceptance in registry"
        
        # Create registry path if needed
        if (-not (Test-Path $Config.RegistryPath)) {
            New-Item -Path $Config.RegistryPath -Force | Out-Null
            Write-Log "Created registry path: $($Config.RegistryPath)"
        }
        
        # Comprehensive acceptance record
        $acceptanceData = @{
            'Accepted'        = @{Value = 1; Type = 'DWord'}
            'AcceptanceDate'  = @{Value = (Get-Date -Format "yyyy-MM-dd HH:mm:ss"); Type = 'String'}
            'TermsVersion'    = @{Value = $Config.TermsVersion; Type = 'String'}
            'ScriptVersion'   = @{Value = $Config.ScriptVersion; Type = 'String'}
            'ComputerName'    = @{Value = $env:COMPUTERNAME; Type = 'String'}
            'UserName'        = @{Value = $env:USERNAME; Type = 'String'}
            'UserDomain'      = @{Value = $env:USERDOMAIN; Type = 'String'}
            'AcceptanceCount' = @{Value = (Get-AcceptanceCount) + 1; Type = 'DWord'}
            'LastReminderCount' = @{Value = 0; Type = 'DWord'}  # Reset reminder count
        }
        
        foreach ($key in $acceptanceData.Keys) {
            $data = $acceptanceData[$key]
            Set-ItemProperty -Path $Config.RegistryPath -Name $key -Value $data.Value -Type $data.Type
        }
        
        Write-Log "Terms acceptance recorded successfully for version $($Config.TermsVersion)" -Level 'SUCCESS'
        return $true
    }
    catch {
        Write-Log "Failed to record terms acceptance: $($_.Exception.Message)" -Level 'ERROR'
        return $false
    }
}

function Test-TermsAcceptance {
    <#
    .SYNOPSIS
        Checks if current terms version has been accepted
    #>
    [CmdletBinding()]
    param()
    
    try {
        if (-not (Test-Path $Config.RegistryPath)) {
            Write-Log "Registry path does not exist - terms not accepted"
            return $false
        }
        
        $acceptance = Get-ItemProperty -Path $Config.RegistryPath -ErrorAction Stop
        $isAccepted = $acceptance.Accepted -eq 1
        $isCurrentVersion = $acceptance.TermsVersion -eq $Config.TermsVersion
        
        if ($isAccepted -and $isCurrentVersion) {
            Write-Log "Terms already accepted for current version $($Config.TermsVersion)" -Level 'SUCCESS'
            return $true
        }
        elseif ($isAccepted -and -not $isCurrentVersion) {
            Write-Log "Terms accepted but version mismatch. Current: $($Config.TermsVersion), Registry: $($acceptance.TermsVersion)" -Level 'WARNING'
            return $false
        }
        else {
            Write-Log "Terms not yet accepted for version $($Config.TermsVersion)"
            return $false
        }
    }
    catch {
        Write-Log "Error checking acceptance status: $($_.Exception.Message)" -Level 'ERROR'
        return $false
    }
}

function Get-AcceptanceCount {
    try {
        if (Test-Path $Config.RegistryPath) {
            $reg = Get-ItemProperty -Path $Config.RegistryPath -Name AcceptanceCount -ErrorAction SilentlyContinue
            return [int]($reg.AcceptanceCount ?? 0)
        }
        return 0
    }
    catch { return 0 }
}

function Update-ReminderCount {
    try {
        if (-not (Test-Path $Config.RegistryPath)) {
            New-Item -Path $Config.RegistryPath -Force | Out-Null
        }
        
        $currentCount = 0
        $existing = Get-ItemProperty -Path $Config.RegistryPath -Name LastReminderCount -ErrorAction SilentlyContinue
        if ($existing) {
            $currentCount = $existing.LastReminderCount
        }
        
        Set-ItemProperty -Path $Config.RegistryPath -Name LastReminderCount -Value ($currentCount + 1) -Type DWord
        Set-ItemProperty -Path $Config.RegistryPath -Name LastReminderDate -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -Type String
        
        return $currentCount + 1
    }
    catch {
        Write-Log "Failed to update reminder count: $($_.Exception.Message)" -Level 'ERROR'
        return 0
    }
}
#endregion

#region Task Management
function New-TermsAcceptanceTask {
    <#
    .SYNOPSIS
        Creates the scheduled task for terms acceptance prompts
    #>
    [CmdletBinding()]
    param()
    
    try {
        Write-Log "Creating terms acceptance scheduled task"
        
        # Generate the user prompt script
        $scriptContent = Get-UserPromptScript
        
        # Ensure script directory exists
        $scriptDir = Split-Path $Config.ScriptFile -Parent
        if (-not (Test-Path $scriptDir)) {
            New-Item -Path $scriptDir -ItemType Directory -Force | Out-Null
            Write-Log "Created script directory: $scriptDir"
        }
        
        # Write the script file
        Set-Content -Path $Config.ScriptFile -Value $scriptContent -Force -Encoding UTF8
        Write-Log "Created user prompt script: $($Config.ScriptFile)"
        
        # Create scheduled task components
        $actionArgs = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($Config.ScriptFile)`""
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $actionArgs
        
        # Multiple triggers for comprehensive coverage
        $triggers = @(
            New-ScheduledTaskTrigger -AtLogOn
            New-ScheduledTaskTrigger -AtStartup
        )
        
        $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\INTERACTIVE" -RunLevel Highest
        
        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -MultipleInstances IgnoreNew `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
        
        # Register the task
        Register-ScheduledTask -TaskName $Config.TaskName -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Force | Out-Null
        
        Write-Log "Scheduled task '$($Config.TaskName)' created successfully" -Level 'SUCCESS'
        return $true
    }
    catch {
        Write-Log "Failed to create scheduled task: $($_.Exception.Message)" -Level 'ERROR'
        return $false
    }
}

function Remove-TermsAcceptanceTask {
    <#
    .SYNOPSIS
        Removes the scheduled task and associated files
    #>
    [CmdletBinding()]
    param()
    
    try {
        Write-Log "Removing terms acceptance components"
        
        # Remove scheduled task
        $task = Get-ScheduledTask -TaskName $Config.TaskName -ErrorAction SilentlyContinue
        if ($task) {
            Unregister-ScheduledTask -TaskName $Config.TaskName -Confirm:$false
            Write-Log "Scheduled task '$($Config.TaskName)' removed" -Level 'SUCCESS'
        } else {
            Write-Log "Scheduled task '$($Config.TaskName)' not found"
        }
        
        # Remove script file
        if (Test-Path $Config.ScriptFile) {
            Remove-Item $Config.ScriptFile -Force
            Write-Log "Script file removed: $($Config.ScriptFile)" -Level 'SUCCESS'
        }
        
        return $true
    }
    catch {
        Write-Log "Failed to remove components: $($_.Exception.Message)" -Level 'ERROR'
        return $false
    }
}
#endregion

#region User Prompt Script Generation
function Get-UserPromptScript {
    <#
    .SYNOPSIS
        Generates the PowerShell script that creates the user acceptance dialog
    #>
    
    return @"
# Terms Acceptance User Interface Script
# Generated by Terms Acceptance System v$($Config.ScriptVersion)
# $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Configuration
`$config = @{
    CompanyName = '$($Config.CompanyName)'
    RegistryPath = '$($Config.RegistryPath)'
    TermsVersion = '$($Config.TermsVersion)'
    ContactNumber = '$($Config.ContactNumber)'
    ContactEmail = '$($Config.ContactEmail)'
    FormTitle = '$($Config.FormTitle)'
    MaxDismissals = $($Config.MaxDismissals)
}

# Function to check current acceptance status
function Test-CurrentAcceptance {
    try {
        if (-not (Test-Path `$config.RegistryPath)) { return `$false }
        `$reg = Get-ItemProperty -Path `$config.RegistryPath -ErrorAction SilentlyContinue
        return (`$reg.Accepted -eq 1 -and `$reg.TermsVersion -eq `$config.TermsVersion)
    }
    catch { return `$false }
}

# Function to get current dismissal count
function Get-DismissalCount {
    try {
        if (Test-Path `$config.RegistryPath) {
            `$reg = Get-ItemProperty -Path `$config.RegistryPath -Name LastReminderCount -ErrorAction SilentlyContinue
            return [int](`$reg.LastReminderCount ?? 0)
        }
        return 0
    }
    catch { return 0 }
}

# Exit if terms are already accepted
if (Test-CurrentAcceptance) { exit 0 }

# Check dismissal count - FORCE ACCEPTANCE MODE
`$dismissalCount = Get-DismissalCount
`$canDismiss = `$false  # DISABLED - No dismissals allowed

# Block Windows key and Alt+Tab to prevent OS interaction
Add-Type -TypeDefinition @"
    using System;
    using System.Diagnostics;
    using System.Runtime.InteropServices;
    using System.Windows.Forms;
    
    public static class KeyboardBlocker {
        private const int HC_ACTION = 0;
        private const int WH_KEYBOARD_LL = 13;
        private const int WH_MOUSE_LL = 14;
        private const int WM_KEYDOWN = 0x0100;
        private const int WM_SYSKEYDOWN = 0x0104;
        private const int VK_LWIN = 0x5B;
        private const int VK_RWIN = 0x5C;
        private const int VK_TAB = 0x09;
        private const int VK_ESCAPE = 0x1B;
        private const int VK_MENU = 0x12;
        
        private static LowLevelKeyboardProc _proc = HookCallback;
        private static IntPtr _hookID = IntPtr.Zero;
        
        public delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);
        
        public static void StartBlocking() {
            _hookID = SetHook(_proc);
        }
        
        public static void StopBlocking() {
            UnhookWindowsHookEx(_hookID);
        }
        
        private static IntPtr SetHook(LowLevelKeyboardProc proc) {
            using (Process curProcess = Process.GetCurrentProcess())
            using (ProcessModule curModule = curProcess.MainModule) {
                return SetWindowsHookEx(WH_KEYBOARD_LL,
                    proc, GetModuleHandle(curModule.ModuleName), 0);
            }
        }
        
        private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam) {
            if (nCode >= 0) {
                if (wParam == (IntPtr)WM_KEYDOWN || wParam == (IntPtr)WM_SYSKEYDOWN) {
                    int vkCode = Marshal.ReadInt32(lParam);
                    
                    // Block Windows keys, Alt+Tab, Ctrl+Alt+Del combinations, Escape
                    if (vkCode == VK_LWIN || vkCode == VK_RWIN || 
                        (vkCode == VK_TAB && (Control.ModifierKeys & Keys.Alt) == Keys.Alt) ||
                        (vkCode == VK_ESCAPE)) {
                        return (IntPtr)1;
                    }
                }
            }
            return CallNextHookEx(_hookID, nCode, wParam, lParam);
        }
        
        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern IntPtr SetWindowsHookEx(int idHook,
            LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);
        
        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool UnhookWindowsHookEx(IntPtr hhk);
        
        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode,
            IntPtr wParam, IntPtr lParam);
        
        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern IntPtr GetModuleHandle(string lpModuleName);
    }
"@

# Start keyboard blocking to prevent OS interaction
[KeyboardBlocker]::StartBlocking()

# Hide taskbar and create fullscreen overlay
Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;
    
    public static class TaskbarHelper {
        [DllImport("user32.dll")]
        private static extern IntPtr FindWindow(string className, string windowText);
        
        [DllImport("user32.dll")]
        private static extern int ShowWindow(IntPtr hwnd, int command);
        
        private const int SW_HIDE = 0;
        private const int SW_SHOW = 1;
        
        public static void HideTaskbar() {
            IntPtr taskbarHandle = FindWindow("Shell_TrayWnd", null);
            IntPtr startHandle = FindWindow("Button", null);
            
            if (taskbarHandle != IntPtr.Zero) {
                ShowWindow(taskbarHandle, SW_HIDE);
            }
            if (startHandle != IntPtr.Zero) {
                ShowWindow(startHandle, SW_HIDE);
            }
        }
        
        public static void ShowTaskbar() {
            IntPtr taskbarHandle = FindWindow("Shell_TrayWnd", null);
            IntPtr startHandle = FindWindow("Button", null);
            
            if (taskbarHandle != IntPtr.Zero) {
                ShowWindow(taskbarHandle, SW_SHOW);
            }
            if (startHandle != IntPtr.Zero) {
                ShowWindow(startHandle, SW_SHOW);
            }
        }
    }
"@

# Hide taskbar during acceptance process
[TaskbarHelper]::HideTaskbar()

# Create fullscreen overlay form first (blocks everything)
`$overlayForm = New-Object System.Windows.Forms.Form -Property @{
    WindowState = 'Maximized'
    FormBorderStyle = 'None'
    TopMost = `$true
    BackColor = [System.Drawing.Color]::FromArgb(200, 0, 0, 0)  # Semi-transparent black
    ShowInTaskbar = `$false
    ControlBox = `$false
    StartPosition = 'Manual'
    Location = New-Object System.Drawing.Point(0, 0)
    Size = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Size
}

# Create main acceptance form (centered on overlay)
`$form = New-Object System.Windows.Forms.Form -Property @{
    Text = `$config.FormTitle
    Size = New-Object System.Drawing.Size($($Config.FormSize.Width), $($Config.FormSize.Height))
    StartPosition = 'CenterScreen'
    TopMost = `$true
    FormBorderStyle = 'FixedDialog'
    MaximizeBox = `$false
    MinimizeBox = `$false
    ControlBox = `$false  # Always disabled - no close button
    BackColor = [System.Drawing.Color]::White
    ShowInTaskbar = `$false
}

# Prevent form from being moved or closed
`$form.Add_FormClosing({
    param(`$sender, `$e)
    if (-not `$script:acceptanceCompleted) {
        `$e.Cancel = `$true  # Prevent closing
    }
})

# Header panel with company branding
`$headerPanel = New-Object System.Windows.Forms.Panel -Property @{
    Dock = 'Top'
    Height = 60
    BackColor = [System.Drawing.Color]::FromArgb(0, 51, 102)
}

`$headerLabel = New-Object System.Windows.Forms.Label -Property @{
    Text = `$config.CompanyName.ToUpper()
    ForeColor = [System.Drawing.Color]::White
    Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
    TextAlign = 'MiddleCenter'
    Dock = 'Fill'
}
`$headerPanel.Controls.Add(`$headerLabel)
`$form.Controls.Add(`$headerPanel)

# Main content area
`$contentPanel = New-Object System.Windows.Forms.Panel -Property @{
    Dock = 'Fill'
    Padding = New-Object System.Windows.Forms.Padding(20)
}

# Terms content (enhanced with more detail)
`$termsText = @"
MANDATORY SECURITY AND USAGE POLICIES

⚠️  SYSTEM LOCKED - YOU MUST ACCEPT TO CONTINUE  ⚠️

You are required to acknowledge and comply with the following security protocols:

8.2.1 WORKSTATION SECURITY
• Lock your workstation immediately when leaving (Windows+L)
• Never share your login credentials with anyone
• Report lost or stolen devices immediately
• Use only approved software and applications

8.10.1 INCIDENT REPORTING
• Report ALL security incidents to the Central Control Center (CCC)
• Emergency Contact: `$(`$config.ContactNumber)
• Email: `$(`$config.ContactEmail)
• Report suspicious emails, malware, or unauthorized access attempts

8.13.2 EMAIL AND COMMUNICATIONS
• Use only authorized departmental email systems
• No personal email accounts for official business
• Professional communication standards apply to all digital correspondence

8.15 DATA PROTECTION
• Handle confidential information according to classification levels
• No storing sensitive data on personal devices or cloud services
• Use encryption for sensitive data transmission

8.16 LEGAL AND COMPLIANCE
• All digital communications are subject to audit and legal discovery
• Maintain professional standards in all digital communications
• Violation of these policies may result in disciplinary action

⚠️  NOTICE: This system is locked until you accept these terms. ⚠️
⚠️  Keyboard shortcuts and system access are disabled. ⚠️
⚠️  Contact IT support if you experience technical issues. ⚠️

By accepting these terms, you acknowledge that you have read, understood, and agree to comply with all stated policies and procedures.

SYSTEM INFORMATION:
Computer: `$env:COMPUTERNAME
User: `$env:USERNAME
Domain: `$env:USERDOMAIN
Date: `$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Terms Version: `$(`$config.TermsVersion)
"@

# Create scrollable text area
`$textBox = New-Object System.Windows.Forms.RichTextBox -Property @{
    Text = `$termsText
    ReadOnly = `$true
    Dock = 'Fill'
    Font = New-Object System.Drawing.Font('Segoe UI', 10)
    BorderStyle = 'FixedSingle'
    BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
}
`$contentPanel.Controls.Add(`$textBox)
`$form.Controls.Add(`$contentPanel)

# Button panel
`$buttonPanel = New-Object System.Windows.Forms.Panel -Property @{
    Dock = 'Bottom'
    Height = 70
    Padding = New-Object System.Windows.Forms.Padding(20, 15, 20, 15)
}

# Accept button (ONLY available option)
`$acceptButton = New-Object System.Windows.Forms.Button -Property @{
    Text = '✓ I ACCEPT - UNLOCK SYSTEM'
    Size = New-Object System.Drawing.Size(300, 50)
    Location = New-Object System.Drawing.Point(([int](`$buttonPanel.Width / 2) - 150), 10)
    BackColor = [System.Drawing.Color]::FromArgb(40, 167, 69)
    ForeColor = [System.Drawing.Color]::White
    Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
    FlatStyle = 'Flat'
    UseVisualStyleBackColor = `$false
}

`$acceptButton.Add_Click({
    try {
        # Set flag to allow form closing
        `$script:acceptanceCompleted = `$true
        
        # Create registry path if needed
        if (-not (Test-Path `$config.RegistryPath)) {
            New-Item -Path `$config.RegistryPath -Force | Out-Null
        }
        
        # Record acceptance with full metadata
        Set-ItemProperty -Path `$config.RegistryPath -Name 'Accepted' -Value 1 -Type DWord
        Set-ItemProperty -Path `$config.RegistryPath -Name 'AcceptanceDate' -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -Type String
        Set-ItemProperty -Path `$config.RegistryPath -Name 'TermsVersion' -Value `$config.TermsVersion -Type String
        Set-ItemProperty -Path `$config.RegistryPath -Name 'ComputerName' -Value `$env:COMPUTERNAME -Type String
        Set-ItemProperty -Path `$config.RegistryPath -Name 'UserName' -Value `$env:USERNAME -Type String
        Set-ItemProperty -Path `$config.RegistryPath -Name 'UserDomain' -Value `$env:USERDOMAIN -Type String
        Set-ItemProperty -Path `$config.RegistryPath -Name 'LastReminderCount' -Value 0 -Type DWord
        
        # Restore system access
        [KeyboardBlocker]::StopBlocking()
        [TaskbarHelper]::ShowTaskbar()
        
        # Show success message
        [System.Windows.Forms.MessageBox]::Show(
            "✅ Terms accepted successfully!`n`nSystem access has been restored.`nThank you for your compliance.",
            "✅ System Unlocked",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        
        # Close forms
        `$overlayForm.Close()
        `$form.Close()
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "❌ Error recording acceptance: `$(`$_.Exception.Message)`n`nPlease contact IT support.",
            "❌ System Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
})

# Warning label (no more dismiss options)
`$warningLabel = New-Object System.Windows.Forms.Label -Property @{
    Text = "⚠️ SYSTEM LOCKED - ACCEPTANCE REQUIRED TO CONTINUE ⚠️"
    Location = New-Object System.Drawing.Point(20, 70)
    Size = New-Object System.Drawing.Size((`$buttonPanel.Width - 40), 30)
    ForeColor = [System.Drawing.Color]::FromArgb(220, 53, 69)
    Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    TextAlign = 'MiddleCenter'
}

`$buttonPanel.Controls.AddRange(@(`$acceptButton, `$warningLabel))
`$form.Controls.Add(`$buttonPanel)

# Initialize acceptance flag
`$script:acceptanceCompleted = `$false

# Set form properties - completely locked down
`$form.AcceptButton = `$acceptButton
`$form.ShowInTaskbar = `$false

# Show overlay first, then main form
try {
    `$overlayForm.Show()
    `$overlayForm.BringToFront()
    
    # Small delay to ensure overlay is rendered
    Start-Sleep -Milliseconds 200
    
    `$form.Show()
    `$form.BringToFront()
    `$form.Focus()
    
    # Keep forms active and focused
    do {
        [System.Windows.Forms.Application]::DoEvents()
        `$form.BringToFront()
        Start-Sleep -Milliseconds 100
    } while (`$form.Visible -and -not `$script:acceptanceCompleted)
}
finally {
    # Cleanup - restore system access even if script fails
    try {
        [KeyboardBlocker]::StopBlocking()
        [TaskbarHelper]::ShowTaskbar()
        if (`$overlayForm) { `$overlayForm.Dispose() }
        if (`$form) { `$form.Dispose() }
    }
    catch {
        # Silent cleanup - don't show errors during cleanup
    }
}
"@
}
#endregion

#region Main Execution
function Start-TermsAcceptanceDeployment {
    <#
    .SYNOPSIS
        Main deployment orchestration function
    #>
    [CmdletBinding()]
    param()
    
    try {
        Start-LogSession
        
        if ($Uninstall) {
            Write-Log "Uninstall operation requested"
            $success = Remove-TermsAcceptanceTask
            
            if ($success) {
                Write-Log "Uninstall completed successfully" -Level 'SUCCESS'
                return 0
            } else {
                Write-Log "Uninstall completed with errors" -Level 'WARNING'
                return 1
            }
        }
        
        # Check current acceptance status
        $alreadyAccepted = Test-TermsAcceptance
        
        if ($alreadyAccepted -and -not $Force) {
            Write-Log "Terms already accepted for current version - no action required" -Level 'SUCCESS'
            return 0
        }
        
        if ($Force) {
            Write-Log "Force parameter specified - recreating task regardless of acceptance status" -Level 'WARNING'
        }
        
        # Deploy the acceptance task
        $success = New-TermsAcceptanceTask
        
        if ($success) {
            Write-Log "Terms acceptance system deployed successfully" -Level 'SUCCESS'
            return 0
        } else {
            Write-Log "Failed to deploy terms acceptance system" -Level 'ERROR'
            return 1
        }
    }
    catch {
        Write-Log "Unexpected error during deployment: $($_.Exception.Message)" -Level 'ERROR'
        Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level 'DEBUG'
        return 1
    }
    finally {
        Write-Log "=== Terms Acceptance Script Completed ===" -Level 'INFO'
    }
}

# Script entry point
try {
    $exitCode = Start-TermsAcceptanceDeployment
    exit $exitCode
}
catch {
    Write-Log "Fatal error in main execution: $($_.Exception.Message)" -Level 'ERROR'
    exit 1
}
#endregion