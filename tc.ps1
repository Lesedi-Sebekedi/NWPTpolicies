<#
.SYNOPSIS
    Pre-Login Terms and Conditions Acceptance Script
.DESCRIPTION
    Displays terms and conditions before user login and requires acceptance
    Runs as SYSTEM account during system startup
.VERSION
    2.1.0
.AUTHOR
    System Administrator
#>

#Requires -Version 3.0

param(
    [switch]$CreateTask,
    [switch]$RunAcceptance,
    [switch]$Uninstall,
    [switch]$TestMode,
    [string]$LogPath = "C:\Windows\Temp\TermsAcceptance.log"
)

# Script Configuration
$SCRIPT_VERSION = "2.1.0"
$TASK_NAME = "AcceptTermsAndConditions"
$COMPANY_NAME = "YourCompany"
$REGISTRY_PATH = "HKLM:\SOFTWARE\$COMPANY_NAME\TermsAcceptance"
$TERMS_VERSION = "2.1.0"

# Global variables
$script:form = $null
$script:acceptButton = $null
$script:declineButton = $null

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$LogPath = $script:LogPath
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] [$SCRIPT_VERSION] $Message"
    
    try {
        Add-Content -Path $LogPath -Value $logEntry -ErrorAction Stop
    }
    catch {
        # If file logging fails, try event log
        try {
            if (-not [System.Diagnostics.EventLog]::SourceExists("TermsAcceptance")) {
                [System.Diagnostics.EventLog]::CreateEventSource("TermsAcceptance", "Application")
            }
            $eventType = switch ($Level) {
                "ERROR" { "Error" }
                "WARN" { "Warning" }
                default { "Information" }
            }
            Write-EventLog -LogName "Application" -Source "TermsAcceptance" `
                -EntryType $eventType -EventId 100 -Message $Message
        }
        catch {
            # Last resort: output to host
            Write-Host $logEntry
        }
    }
}

function Test-Prerequisites {
    Write-Log "Testing prerequisites..."
    
    $issues = @()
    
    # Check PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 3) {
        $issues += "PowerShell 3.0 or higher required. Current version: $($PSVersionTable.PSVersion)"
    }
    
    # Check .NET Framework for GUI
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    }
    catch {
        $issues += ".NET Framework Windows Forms not available: $($_.Exception.Message)"
    }
    
    # Check running as SYSTEM or Administrator
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $identity.IsSystem) {
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            $issues += "Script must run as SYSTEM or Administrator"
        }
    }
    
    if ($issues.Count -gt 0) {
        Write-Log "Prerequisite check failed: $($issues -join '; ')" -Level "ERROR"
        return $false
    }
    
    Write-Log "All prerequisites satisfied"
    return $true
}

function Set-RegistryAcceptance {
    param(
        [bool]$Accepted,
        [string]$AcceptedBy = "System"
    )
    
    try {
        if (-not (Test-Path $REGISTRY_PATH)) {
            New-Item -Path $REGISTRY_PATH -Force | Out-Null
        }
        
        Set-ItemProperty -Path $REGISTRY_PATH -Name "Accepted" -Value ([int]$Accepted) -Type DWord
        Set-ItemProperty -Path $REGISTRY_PATH -Name "AcceptanceDate" -Value (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Set-ItemProperty -Path $REGISTRY_PATH -Name "AcceptedBy" -Value $AcceptedBy
        Set-ItemProperty -Path $REGISTRY_PATH -Name "TermsVersion" -Value $TERMS_VERSION
        Set-ItemProperty -Path $REGISTRY_PATH -Name "ScriptVersion" -Value $SCRIPT_VERSION
        
        # Set registry permissions
        $acl = Get-Acl $REGISTRY_PATH
        $rule = New-Object System.Security.AccessControl.RegistryAccessRule(
            "Users", "Read", "Allow"
        )
        $acl.SetAccessRule($rule)
        Set-Acl -Path $REGISTRY_PATH -AclObject $acl
        
        Write-Log "Registry acceptance set to: $Accepted"
        return $true
    }
    catch {
        Write-Log "Error setting registry acceptance: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Test-IfAlreadyAccepted {
    try {
        if (Test-Path $REGISTRY_PATH) {
            $accepted = Get-ItemProperty -Path $REGISTRY_PATH -Name "Accepted" -ErrorAction SilentlyContinue
            $storedVersion = Get-ItemProperty -Path $REGISTRY_PATH -Name "TermsVersion" -ErrorAction SilentlyContinue
            
            if ($accepted -and $accepted.Accepted -eq 1) {
                # Check if terms version changed
                if ($storedVersion -and $storedVersion.TermsVersion -eq $TERMS_VERSION) {
                    Write-Log "Terms already accepted (Version: $TERMS_VERSION)"
                    return $true
                }
                else {
                    Write-Log "Terms version changed ($($storedVersion.TermsVersion) -> $TERMS_VERSION), requiring re-acceptance"
                    return $false
                }
            }
        }
        return $false
    }
    catch {
        Write-Log "Error checking acceptance status: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Get-TermsText {
    @"
TERMS AND CONDITIONS - VERSION $TERMS_VERSION

Please read these terms and conditions carefully before proceeding.

1. ACCEPTANCE OF TERMS
By accessing and using this system, you agree to be bound by these terms and conditions.

2. USER RESPONSIBILITIES
- You are responsible for maintaining the confidentiality of your account
- You agree to use the system in compliance with all applicable laws
- You will not attempt to circumvent security measures
- You will report any security vulnerabilities immediately

3. PRIVACY POLICY
Your use of this system is subject to our privacy policy, which governs the collection and use of information.
All activities are logged and monitored for security purposes.

4. SYSTEM USAGE
- The system is provided for authorized use only
- Unauthorized access or use is strictly prohibited
- All activities may be monitored and logged
- Misuse may result in account termination and legal action

5. INTELLECTUAL PROPERTY
All content and systems are property of $COMPANY_NAME
Unauthorized copying or distribution is prohibited

6. LIMITATION OF LIABILITY
$COMPANY_NAME is not liable for any indirect, incidental, or consequential damages

7. ACCEPTANCE
By clicking 'I Accept', you acknowledge that you have:
- Read and understood these terms
- Agree to be bound by them
- Understand the privacy implications

If you do not agree to these terms, click 'I Decline' and the system may not be accessible.

Last Updated: $(Get-Date -Format "yyyy-MM-dd")
System: $env:COMPUTERNAME
"@
}

function Show-TermsAndConditions {
    try {
        Write-Log "Creating terms and conditions dialog..."
        
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        
        $form = New-Object System.Windows.Forms.Form
        $form.Text = "Terms and Conditions Acceptance - $COMPANY_NAME"
        $form.Size = New-Object System.Drawing.Size(700, 550)
        $form.StartPosition = "CenterScreen"
        $form.FormBorderStyle = "FixedDialog"
        $form.MaximizeBox = $false
        $form.MinimizeBox = $false
        $form.TopMost = $true
        $form.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
        $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        
        # Get primary monitor for centering
        $primaryScreen = [System.Windows.Forms.Screen]::PrimaryScreen
        $form.Location = New-Object System.Drawing.Point(
            ($primaryScreen.Bounds.Width - $form.Width) / 2,
            ($primaryScreen.Bounds.Height - $form.Height) / 2
        )
        
        # Title label
        $titleLabel = New-Object System.Windows.Forms.Label
        $titleLabel.Location = New-Object System.Drawing.Point(20, 15)
        $titleLabel.Size = New-Object System.Drawing.Size(650, 25)
        $titleLabel.Text = "TERMS AND CONDITIONS ACCEPTANCE"
        $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
        $titleLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $form.Controls.Add($titleLabel)
        
        # Text box for terms with scrollbars
        $textBox = New-Object System.Windows.Forms.RichTextBox
        $textBox.Location = New-Object System.Drawing.Point(20, 50)
        $textBox.Size = New-Object System.Drawing.Size(650, 380)
        $textBox.Text = Get-TermsText
        $textBox.ReadOnly = $true
        $textBox.BackColor = [System.Drawing.Color]::White
        $textBox.ForeColor = [System.Drawing.Color]::Black
        $textBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $form.Controls.Add($textBox)
        
        # Accept button
        $acceptButton = New-Object System.Windows.Forms.Button
        $acceptButton.Location = New-Object System.Drawing.Point(200, 450)
        $acceptButton.Size = New-Object System.Drawing.Size(120, 35)
        $acceptButton.Text = "I Accept"
        $acceptButton.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $acceptButton.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
        $acceptButton.ForeColor = [System.Drawing.Color]::White
        $acceptButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $acceptButton.DialogResult = [System.Windows.Forms.DialogResult]::Yes
        $form.Controls.Add($acceptButton)
        
        # Decline button
        $declineButton = New-Object System.Windows.Forms.Button
        $declineButton.Location = New-Object System.Drawing.Point(350, 450)
        $declineButton.Size = New-Object System.Drawing.Size(120, 35)
        $declineButton.Text = "I Decline"
        $declineButton.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $declineButton.DialogResult = [System.Windows.Forms.DialogResult]::No
        $form.Controls.Add($declineButton)
        
        # Store references for cleanup
        $script:form = $form
        $script:acceptButton = $acceptButton
        $script:declineButton = $declineButton
        
        Write-Log "Showing terms dialog..."
        $result = $form.ShowDialog()
        
        return $result
    }
    catch {
        Write-Log "Error displaying terms: $($_.Exception.Message)" -Level "ERROR"
        return [System.Windows.Forms.DialogResult]::No
    }
}

function Invoke-Cleanup {
    try {
        if ($script:form -and !$script:form.IsDisposed) {
            $script:form.Dispose()
        }
        
        # Clean up temporary files older than 7 days
        Get-ChildItem -Path "C:\Windows\Temp" -Filter "*TermsAcceptance*" -File | 
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | 
            Remove-Item -Force -ErrorAction SilentlyContinue
            
        Write-Log "Cleanup completed successfully"
    }
    catch {
        Write-Log "Cleanup error: $($_.Exception.Message)" -Level "WARN"
    }
}

function Accept-Terms {
    try {
        Write-Log "Starting terms acceptance process..."
        
        # Check if already accepted
        if (Test-IfAlreadyAccepted) {
            return $true
        }
        
        # Show terms and get acceptance
        $result = Show-TermsAndConditions
        
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            Write-Log "User accepted terms and conditions"
            
            if (Set-RegistryAcceptance -Accepted $true -AcceptedBy "PreLoginUser") {
                Write-Log "Terms acceptance recorded successfully"
                return $true
            }
            else {
                Write-Log "Failed to record terms acceptance" -Level "ERROR"
                return $false
            }
        }
        else {
            Write-Log "User declined terms and conditions"
            
            # Optional: Add actions for declined terms
            # For example: restart, shutdown, or limited access
            if (-not $script:TestMode) {
                Write-Log "System access requires acceptance of terms" -Level "WARN"
                # Start-Sleep -Seconds 30
                # Restart-Computer -Force
            }
            
            return $false
        }
    }
    catch {
        Write-Log "Error in terms acceptance process: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
    finally {
        Invoke-Cleanup
    }
}

function Create-StartupTask {
    try {
        Write-Log "Creating scheduled task..."
        
        $scriptPath = $MyInvocation.MyCommand.Path
        $psExe = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
        
        $action = New-ScheduledTaskAction -Execute $psExe -Argument @(
            "-ExecutionPolicy Bypass",
            "-File `"$scriptPath`"",
            "-RunAcceptance",
            "-LogPath `"$LogPath`""
        ) -ErrorAction Stop
        
        $trigger = New-ScheduledTaskTrigger -AtStartup -ErrorAction Stop
        
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries -StartWhenAvailable `
            -MultipleInstances IgnoreNew -RestartCount 3 `
            -RestartInterval (New-TimeSpan -Minutes 1) -ErrorAction Stop
        
        $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" `
            -LogonType ServiceAccount -RunLevel Highest -ErrorAction Stop
        
        # Register the task
        $task = Register-ScheduledTask -TaskName $TASK_NAME `
            -Action $action -Trigger $trigger -Settings $settings `
            -Principal $principal -Force -ErrorAction Stop
        
        # Set task description
        $task | Set-ScheduledTask -Description "Accepts terms and conditions before user login" -ErrorAction SilentlyContinue
        
        Write-Log "Scheduled task '$TASK_NAME' created successfully"
        return $true
    }
    catch {
        Write-Log "Error creating scheduled task: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Remove-StartupTask {
    try {
        Write-Log "Removing scheduled task..."
        
        Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false -ErrorAction Stop
        
        # Remove registry entries
        if (Test-Path $REGISTRY_PATH) {
            Remove-Item -Path $REGISTRY_PATH -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        Write-Log "Scheduled task and registry entries removed successfully"
        return $true
    }
    catch {
        Write-Log "Error removing scheduled task: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Optimize-Startup {
    # Set process priority to avoid impacting system startup
    try {
        $process = Get-Process -Id $pid
        $process.PriorityClass = "BelowNormal"
        Write-Log "Process priority set to BelowNormal"
    }
    catch {
        Write-Log "Could not set process priority: $($_.Exception.Message)" -Level "WARN"
    }
    
    # Small delay to avoid startup contention
    Start-Sleep -Seconds 5
}

# Main execution
try {
    Write-Log "Script started with parameters: $($PSBoundParameters | ConvertTo-Json)"
    
    if (-not (Test-Prerequisites)) {
        Write-Log "Prerequisite check failed. Exiting." -Level "ERROR"
        exit 1
    }
    
    if ($Uninstall) {
        if (Remove-StartupTask) {
            Write-Log "Uninstallation completed successfully"
            exit 0
        }
        else {
            Write-Log "Uninstallation failed" -Level "ERROR"
            exit 1
        }
    }
    
    if ($CreateTask) {
        if (Create-StartupTask) {
            Write-Log "Setup completed successfully. Task will run on next startup."
            exit 0
        }
        else {
            Write-Log "Setup failed" -Level "ERROR"
            exit 1
        }
    }
    
    if ($RunAcceptance) {
        if ($TestMode) {
            Write-Log "Running in test mode - no system actions will be taken"
        }
        
        Optimize-Startup
        
        if (Accept-Terms) {
            Write-Log "Terms acceptance process completed successfully"
            exit 0
        }
        else {
            Write-Log "Terms acceptance process failed or was declined" -Level "WARN"
            exit 1
        }
    }
    
    # Show usage if no parameters specified
    Write-Host @"
Terms and Conditions Acceptance Script - Version $SCRIPT_VERSION

Usage:
    .\TermsAcceptance.ps1 -CreateTask   : Creates scheduled task for startup
    .\TermsAcceptance.ps1 -RunAcceptance : Runs terms acceptance process
    .\TermsAcceptance.ps1 -Uninstall     : Removes scheduled task and cleanup
    .\TermsAcceptance.ps1 -TestMode      : Test mode (use with -RunAcceptance)

Examples:
    # Create the startup task (run as Administrator)
    .\TermsAcceptance.ps1 -CreateTask

    # Test the acceptance process
    .\TermsAcceptance.ps1 -RunAcceptance -TestMode

    # Uninstall completely
    .\TermsAcceptance.ps1 -Uninstall

Logs are stored in: $LogPath
"@
}
catch {
    $errorMsg = $_.Exception.Message
    Write-Log "Unhandled error in main execution: $errorMsg" -Level "ERROR"
    exit 1
}
finally {
    Write-Log "Script execution completed"
}