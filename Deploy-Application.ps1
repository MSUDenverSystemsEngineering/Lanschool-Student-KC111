<#
.SYNOPSIS
	This script performs the installation or uninstallation of an application(s).
	# LICENSE #
	PowerShell App Deployment Toolkit - Provides a set of functions to perform common application deployment tasks on Windows.
	Copyright (C) 2017 - Sean Lillis, Dan Cunningham, Muhammad Mashwani, Aman Motazedian.
	This program is free software: you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the Free Software Foundation, either version 3 of the License, or any later version. This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
	You should have received a copy of the GNU Lesser General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.
.DESCRIPTION
	The script is provided as a template to perform an install or uninstall of an application(s).
	The script either performs an "Install" deployment type or an "Uninstall" deployment type.
	The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.
	The script dot-sources the AppDeployToolkitMain.ps1 script which contains the logic and functions required to install or uninstall an application.
.PARAMETER DeploymentType
	The type of deployment to perform. Default is: Install.
.PARAMETER DeployMode
	Specifies whether the installation should be run in Interactive, Silent, or NonInteractive mode. Default is: Interactive. Options: Interactive = Shows dialogs, Silent = No dialogs, NonInteractive = Very silent, i.e. no blocking apps. NonInteractive mode is automatically set if it is detected that the process is not user interactive.
.PARAMETER AllowRebootPassThru
	Allows the 3010 return code (requires restart) to be passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.
.PARAMETER TerminalServerMode
	Changes to "user install mode" and back to "user execute mode" for installing/uninstalling applications for Remote Destkop Session Hosts/Citrix servers.
.PARAMETER DisableLogging
	Disables logging to file for the script. Default is: $false.
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeployMode 'Silent'; Exit $LastExitCode }"
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -AllowRebootPassThru; Exit $LastExitCode }"
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeploymentType 'Uninstall'; Exit $LastExitCode }"
.EXAMPLE
    Deploy-Application.exe -DeploymentType "Install" -DeployMode "Silent"
.NOTES
	Toolkit Exit Code Ranges:
	60000 - 68999: Reserved for built-in exit codes in Deploy-Application.ps1, Deploy-Application.exe, and AppDeployToolkitMain.ps1
	69000 - 69999: Recommended for user customized exit codes in Deploy-Application.ps1
	70000 - 79999: Recommended for user customized exit codes in AppDeployToolkitExtensions.ps1
.LINK
	http://psappdeploytoolkit.com
#>

## Suppress PSScriptAnalyzer errors for not using declared variables during AppVeyor build
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "", Justification="Suppress AppVeyor errors on unused variables below")]

[CmdletBinding()]
Param (
	[Parameter(Mandatory=$false)]
	[ValidateSet('Install','Uninstall','Repair')]
	[string]$DeploymentType = 'Install',
	[Parameter(Mandatory=$false)]
	[ValidateSet('Interactive','Silent','NonInteractive')]
	[string]$DeployMode = 'Interactive',
	[Parameter(Mandatory=$false)]
	[switch]$AllowRebootPassThru = $false,
	[Parameter(Mandatory=$false)]
	[switch]$TerminalServerMode = $false,
	[Parameter(Mandatory=$false)]
	[switch]$DisableLogging = $false
)

Try {
	## Set the script execution policy for this process
	Try { Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force -ErrorAction 'Stop' } Catch { Write-Error "Failed to set the execution policy to Bypass for this process." }

	##*===============================================
	##* VARIABLE DECLARATION
	##*===============================================
	## Variables: Application
	[string]$appVendor = 'Lenvo'
	[string]$appName = 'Lanschool'
	[string]$appVersion = 'v8.0.1.154'
	[string]$appArch = 'x86'
	[string]$appLang = 'EN'
	[string]$appRevision = '01'
	[string]$appScriptVersion = '1.0.0'
	[string]$appScriptDate = '02/15/2020'
	[string]$appScriptAuthor = 'David Torres'
	##*===============================================
	## Variables: Install Titles (Only set here to override defaults set by the toolkit)
	[string]$installName = ''
	[string]$installTitle = ''

	##* Do not modify section below
	#region DoNotModify

	## Variables: Exit Code
	[int32]$mainExitCode = 0

	## Variables: Script
	[string]$deployAppScriptFriendlyName = 'Deploy Application'
	[version]$deployAppScriptVersion = [version]'3.8.3'
	[string]$deployAppScriptDate = '30/09/2020'
	[hashtable]$deployAppScriptParameters = $psBoundParameters

	## Variables: Environment
	If (Test-Path -LiteralPath 'variable:HostInvocation') { $InvocationInfo = $HostInvocation } Else { $InvocationInfo = $MyInvocation }
	[string]$scriptDirectory = Split-Path -Path $InvocationInfo.MyCommand.Definition -Parent

	## Dot source the required App Deploy Toolkit Functions
	Try {
		[string]$moduleAppDeployToolkitMain = "$scriptDirectory\AppDeployToolkit\AppDeployToolkitMain.ps1"
		If (-not (Test-Path -LiteralPath $moduleAppDeployToolkitMain -PathType 'Leaf')) { Throw "Module does not exist at the specified location [$moduleAppDeployToolkitMain]." }
		If ($DisableLogging) { . $moduleAppDeployToolkitMain -DisableLogging } Else { . $moduleAppDeployToolkitMain }
	}
	Catch {
		If ($mainExitCode -eq 0){ [int32]$mainExitCode = 60008 }
		Write-Error -Message "Module [$moduleAppDeployToolkitMain] failed to load: `n$($_.Exception.Message)`n `n$($_.InvocationInfo.PositionMessage)" -ErrorAction 'Continue'
		## Exit the script, returning the exit code to SCCM
		If (Test-Path -LiteralPath 'variable:HostInvocation') { $script:ExitCode = $mainExitCode; Exit } Else { Exit $mainExitCode }
	}

	#endregion
	##* Do not modify section above
	##*===============================================
	##* END VARIABLE DECLARATION
	##*===============================================

	If ($deploymentType -ine 'Uninstall' -and $deploymentType -ine 'Repair') {
		##*===============================================
		##* PRE-INSTALLATION
		##*===============================================
		[string]$installPhase = 'Pre-Installation'

		## Show Welcome Message, close Internet Explorer if required, verify there is enough disk space to complete the install, and persist the prompt
		Show-InstallationWelcome -CloseApps 'iexplore' -CheckDiskSpace -PersistPrompt

		## Show Progress Message (with the default message)
		Show-InstallationProgress

		## <Perform Pre-Installation tasks here>


		##*===============================================
		##* INSTALLATION
		##*===============================================
		[string]$installPhase = 'Installation'

		## Handle Zero-Config MSI Installations
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Install'; Path = $defaultMsiFile }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat; If ($defaultMspFiles) { $defaultMspFiles | ForEach-Object { Execute-MSI -Action 'Patch' -Path $_ } }
		}

		## <Perform Installation tasks here>
		$exitCode = Execute-MSI -Action 'Install' -Path "$dirFiles\Student.msi" -AddParameters '/qn ADVANCE_OPTIONS=1 SECURE_MODE=1 PASSWORD=KC111 PASSWORD_CONFIRM=KC111 CHANNEL=111'
		If (($exitCode.ExitCode -ne "0") -and ($mainExitCode -ne "3010")) {$mainExitCode =$exitCode.ExitCode }
		##*===============================================
		##* POST-INSTALLATION
		##*===============================================
		[string]$installPhase = 'Post-Installation'

		## <Perform Post-Installation tasks here>

		## Display a message at the end of the install
		If (-not $useDefaultMsi) {}
	}
	ElseIf ($deploymentType -ieq 'Uninstall')
	{
		##*===============================================
		##* PRE-UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Pre-Uninstallation'

		## Show Welcome Message, close Internet Explorer with a 60 second countdown before automatically closing
		Show-InstallationWelcome -CloseApps 'iexplore' -CloseAppsCountdown 60

		## Show Progress Message (with the default message)
		Show-InstallationProgress

		## <Perform Pre-Uninstallation tasks here>


		##*===============================================
		##* UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Uninstallation'

		## Handle Zero-Config MSI Uninstallations
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Uninstall'; Path = $defaultMsiFile }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat
		}

		# <Perform Uninstallation tasks here>
		$exitCode = Execute-MSI -Action 'Uninstall' -Path "$dirFiles\Student.msi" -AddParameters '/QN'
		If (($exitCode.ExitCode -ne "0") -and ($mainExitCode -ne "3010")) { $mainExitCode = $exitCode.ExitCode }

		##*===============================================
		##* POST-UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Post-Uninstallation'

		## <Perform Post-Uninstallation tasks here>


	}
	ElseIf ($deploymentType -ieq 'Repair')
	{
		##*===============================================
		##* PRE-REPAIR
		##*===============================================
		[string]$installPhase = 'Pre-Repair'

		## Show Progress Message (with the default message)
		Show-InstallationProgress

		## <Perform Pre-Repair tasks here>

		##*===============================================
		##* REPAIR
		##*===============================================
		[string]$installPhase = 'Repair'

		## Handle Zero-Config MSI Repairs
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Repair'; Path = $defaultMsiFile; }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat
		}
		# <Perform Repair tasks here>

		##*===============================================
		##* POST-REPAIR
		##*===============================================
		[string]$installPhase = 'Post-Repair'

		## <Perform Post-Repair tasks here>


	}
	##*===============================================
	##* END SCRIPT BODY
	##*===============================================

	## Call the Exit-Script function to perform final cleanup operations
	Exit-Script -ExitCode $mainExitCode
}
Catch {
	[int32]$mainExitCode = 60001
	[string]$mainErrorMessage = "$(Resolve-Error)"
	Write-Log -Message $mainErrorMessage -Severity 3 -Source $deployAppScriptFriendlyName
	Show-DialogBox -Text $mainErrorMessage -Icon 'Stop'
	Exit-Script -ExitCode $mainExitCode
}

# SIG # Begin signature block
# MIIUEwYJKoZIhvcNAQcCoIIUBDCCFAACAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDYbEN3bCydpB1z
# HrMXJ+p0ASXPV1KRR8GMo8AiUHLf0aCCESYwggWBMIIEaaADAgECAhA5ckQ6+SK3
# UdfTbBDdMTWVMA0GCSqGSIb3DQEBDAUAMHsxCzAJBgNVBAYTAkdCMRswGQYDVQQI
# DBJHcmVhdGVyIE1hbmNoZXN0ZXIxEDAOBgNVBAcMB1NhbGZvcmQxGjAYBgNVBAoM
# EUNvbW9kbyBDQSBMaW1pdGVkMSEwHwYDVQQDDBhBQUEgQ2VydGlmaWNhdGUgU2Vy
# dmljZXMwHhcNMTkwMzEyMDAwMDAwWhcNMjgxMjMxMjM1OTU5WjCBiDELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCk5ldyBKZXJzZXkxFDASBgNVBAcTC0plcnNleSBDaXR5
# MR4wHAYDVQQKExVUaGUgVVNFUlRSVVNUIE5ldHdvcmsxLjAsBgNVBAMTJVVTRVJU
# cnVzdCBSU0EgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQCAEmUXNg7D2wiz0KxXDXbtzSfTTK1Qg2HiqiBNCS1k
# CdzOiZ/MPans9s/B3PHTsdZ7NygRK0faOca8Ohm0X6a9fZ2jY0K2dvKpOyuR+OJv
# 0OwWIJAJPuLodMkYtJHUYmTbf6MG8YgYapAiPLz+E/CHFHv25B+O1ORRxhFnRghR
# y4YUVD+8M/5+bJz/Fp0YvVGONaanZshyZ9shZrHUm3gDwFA66Mzw3LyeTP6vBZY1
# H1dat//O+T23LLb2VN3I5xI6Ta5MirdcmrS3ID3KfyI0rn47aGYBROcBTkZTmzNg
# 95S+UzeQc0PzMsNT79uq/nROacdrjGCT3sTHDN/hMq7MkztReJVni+49Vv4M0GkP
# Gw/zJSZrM233bkf6c0Plfg6lZrEpfDKEY1WJxA3Bk1QwGROs0303p+tdOmw1XNtB
# 1xLaqUkL39iAigmTYo61Zs8liM2EuLE/pDkP2QKe6xJMlXzzawWpXhaDzLhn4ugT
# ncxbgtNMs+1b/97lc6wjOy0AvzVVdAlJ2ElYGn+SNuZRkg7zJn0cTRe8yexDJtC/
# QV9AqURE9JnnV4eeUB9XVKg+/XRjL7FQZQnmWEIuQxpMtPAlR1n6BB6T1CZGSlCB
# st6+eLf8ZxXhyVeEHg9j1uliutZfVS7qXMYoCAQlObgOK6nyTJccBz8NUvXt7y+C
# DwIDAQABo4HyMIHvMB8GA1UdIwQYMBaAFKARCiM+lvEH7OKvKe+CpX/QMKS0MB0G
# A1UdDgQWBBRTeb9aqitKz1SA4dibwJ3ysgNmyzAOBgNVHQ8BAf8EBAMCAYYwDwYD
# VR0TAQH/BAUwAwEB/zARBgNVHSAECjAIMAYGBFUdIAAwQwYDVR0fBDwwOjA4oDag
# NIYyaHR0cDovL2NybC5jb21vZG9jYS5jb20vQUFBQ2VydGlmaWNhdGVTZXJ2aWNl
# cy5jcmwwNAYIKwYBBQUHAQEEKDAmMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5j
# b21vZG9jYS5jb20wDQYJKoZIhvcNAQEMBQADggEBABiHUdx0IT2ciuAntzPQLszs
# 8ObLXhHeIm+bdY6ecv7k1v6qH5yWLe8DSn6u9I1vcjxDO8A/67jfXKqpxq7y/Nju
# o3tD9oY2fBTgzfT3P/7euLSK8JGW/v1DZH79zNIBoX19+BkZyUIrE79Yi7qkomYE
# doiRTgyJFM6iTckys7roFBq8cfFb8EELmAAKIgMQ5Qyx+c2SNxntO/HkOrb5RRMm
# da+7qu8/e3c70sQCkT0ZANMXXDnbP3sYDUXNk4WWL13fWRZPP1G91UUYP+1KjugG
# YXQjFrUNUHMnREd/EF2JKmuFMRTE6KlqTIC8anjPuH+OdnKZDJ3+15EIFqGjX5Uw
# ggWuMIIElqADAgECAhAHA3HRD3laQHGZK5QHYpviMA0GCSqGSIb3DQEBCwUAMHwx
# CzAJBgNVBAYTAlVTMQswCQYDVQQIEwJNSTESMBAGA1UEBxMJQW5uIEFyYm9yMRIw
# EAYDVQQKEwlJbnRlcm5ldDIxETAPBgNVBAsTCEluQ29tbW9uMSUwIwYDVQQDExxJ
# bkNvbW1vbiBSU0EgQ29kZSBTaWduaW5nIENBMB4XDTE4MDYyMTAwMDAwMFoXDTIx
# MDYyMDIzNTk1OVowgbkxCzAJBgNVBAYTAlVTMQ4wDAYDVQQRDAU4MDIwNDELMAkG
# A1UECAwCQ08xDzANBgNVBAcMBkRlbnZlcjEYMBYGA1UECQwPMTIwMSA1dGggU3Ry
# ZWV0MTAwLgYDVQQKDCdNZXRyb3BvbGl0YW4gU3RhdGUgVW5pdmVyc2l0eSBvZiBE
# ZW52ZXIxMDAuBgNVBAMMJ01ldHJvcG9saXRhbiBTdGF0ZSBVbml2ZXJzaXR5IG9m
# IERlbnZlcjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMtXiSjEDjYN
# BIYXsPnFGHwZqvS5lgRNSaQjsyxgLsGI6yLLDCpaYy3CBwN1on4QnYzEQpsHV+TJ
# /3K61ZvqAxhR6Anw8TjVjaB3kPdtKJjEUlgiXNK0nDRyMVasZyeXALR5STSf1Sxo
# Mt8HIDd0KTB8yhME6ezFdFzwB5He2/jyOswfYsN+n4k2Q9UcaVtWgCzWua39anwN
# va7M4GugPO5ZkF6XkrGzRHpXctV/Fk6LmqPY6sRm45nScnC1KQ3NN/t6ZBHzmAtg
# bZa41o5+AvNdkv9TVF6S3ODGpf3qKW8kjFt82LLYdZi0V07ln+S/BtAlGUPOvqem
# 4EkbMtZ5M3MCAwEAAaOCAewwggHoMB8GA1UdIwQYMBaAFK41Ixf//wY9nFDgjCRl
# Mx5wEIiiMB0GA1UdDgQWBBSl6YhuvPlIpfXzOIq+Y/mkDGObDzAOBgNVHQ8BAf8E
# BAMCB4AwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcDAzARBglghkgB
# hvhCAQEEBAMCBBAwZgYDVR0gBF8wXTBbBgwrBgEEAa4jAQQDAgEwSzBJBggrBgEF
# BQcCARY9aHR0cHM6Ly93d3cuaW5jb21tb24ub3JnL2NlcnQvcmVwb3NpdG9yeS9j
# cHNfY29kZV9zaWduaW5nLnBkZjBJBgNVHR8EQjBAMD6gPKA6hjhodHRwOi8vY3Js
# LmluY29tbW9uLXJzYS5vcmcvSW5Db21tb25SU0FDb2RlU2lnbmluZ0NBLmNybDB+
# BggrBgEFBQcBAQRyMHAwRAYIKwYBBQUHMAKGOGh0dHA6Ly9jcnQuaW5jb21tb24t
# cnNhLm9yZy9JbkNvbW1vblJTQUNvZGVTaWduaW5nQ0EuY3J0MCgGCCsGAQUFBzAB
# hhxodHRwOi8vb2NzcC5pbmNvbW1vbi1yc2Eub3JnMC0GA1UdEQQmMCSBIml0c3N5
# c3RlbWVuZ2luZWVyaW5nQG1zdWRlbnZlci5lZHUwDQYJKoZIhvcNAQELBQADggEB
# AIc2PVq7BamWAujyCQPHsGCDbM3i1OY5nruA/fOtbJ6mJvT9UJY4+61grcHLzV7o
# p1y0nRhV459TrKfHKO42uRyZpdnHaOoC080cfg/0EwFJRy3bYB0vkVP8TeUkvUhb
# tcPVofI1P/wh9ZT2iYVCerOOAqivxWqh8Dt+8oSbjSGhPFWyu04b8UczbK/97uXd
# gK0zNcXDJUjMKr6CbevfLQLfQiFPizaej+2fvR/jZHAvxO9W2rhd6Nw6gFs2q3P4
# CFK0+yAkFCLk+9wsp+RsRvRkvdWJp+anNvAKOyVfCj6sz5dQPAIYIyLhy9ze3taV
# Km99DQQZV/wN/ATPDftLGm0wggXrMIID06ADAgECAhBl4eLj1d5QRYXzJiSABeLU
# MA0GCSqGSIb3DQEBDQUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMKTmV3IEpl
# cnNleTEUMBIGA1UEBxMLSmVyc2V5IENpdHkxHjAcBgNVBAoTFVRoZSBVU0VSVFJV
# U1QgTmV0d29yazEuMCwGA1UEAxMlVVNFUlRydXN0IFJTQSBDZXJ0aWZpY2F0aW9u
# IEF1dGhvcml0eTAeFw0xNDA5MTkwMDAwMDBaFw0yNDA5MTgyMzU5NTlaMHwxCzAJ
# BgNVBAYTAlVTMQswCQYDVQQIEwJNSTESMBAGA1UEBxMJQW5uIEFyYm9yMRIwEAYD
# VQQKEwlJbnRlcm5ldDIxETAPBgNVBAsTCEluQ29tbW9uMSUwIwYDVQQDExxJbkNv
# bW1vbiBSU0EgQ29kZSBTaWduaW5nIENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A
# MIIBCgKCAQEAwKAvix56u2p1rPg+3KO6OSLK86N25L99MCfmutOYMlYjXAaGlw2A
# 6O2igTXrC/Zefqk+aHP9ndRnec6q6mi3GdscdjpZh11emcehsriphHMMzKuHRhxq
# x+85Jb6n3dosNXA2HSIuIDvd4xwOPzSf5X3+VYBbBnyCV4RV8zj78gw2qblessWB
# RyN9EoGgwAEoPgP5OJejrQLyAmj91QGr9dVRTVDTFyJG5XMY4DrkN3dRyJ59UopP
# gNwmucBMyvxR+hAJEXpXKnPE4CEqbMJUvRw+g/hbqSzx+tt4z9mJmm2j/w2nP35M
# ViPWCb7hpR2LB8W/499Yqu+kr4LLBfgKCQIDAQABo4IBWjCCAVYwHwYDVR0jBBgw
# FoAUU3m/WqorSs9UgOHYm8Cd8rIDZsswHQYDVR0OBBYEFK41Ixf//wY9nFDgjCRl
# Mx5wEIiiMA4GA1UdDwEB/wQEAwIBhjASBgNVHRMBAf8ECDAGAQH/AgEAMBMGA1Ud
# JQQMMAoGCCsGAQUFBwMDMBEGA1UdIAQKMAgwBgYEVR0gADBQBgNVHR8ESTBHMEWg
# Q6BBhj9odHRwOi8vY3JsLnVzZXJ0cnVzdC5jb20vVVNFUlRydXN0UlNBQ2VydGlm
# aWNhdGlvbkF1dGhvcml0eS5jcmwwdgYIKwYBBQUHAQEEajBoMD8GCCsGAQUFBzAC
# hjNodHRwOi8vY3J0LnVzZXJ0cnVzdC5jb20vVVNFUlRydXN0UlNBQWRkVHJ1c3RD
# QS5jcnQwJQYIKwYBBQUHMAGGGWh0dHA6Ly9vY3NwLnVzZXJ0cnVzdC5jb20wDQYJ
# KoZIhvcNAQENBQADggIBAEYstn9qTiVmvZxqpqrQnr0Prk41/PA4J8HHnQTJgjTb
# huET98GWjTBEE9I17Xn3V1yTphJXbat5l8EmZN/JXMvDNqJtkyOh26owAmvquMCF
# 1pKiQWyuDDllxR9MECp6xF4wnH1Mcs4WeLOrQPy+C5kWE5gg/7K6c9G1VNwLkl/p
# o9ORPljxKKeFhPg9+Ti3JzHIxW7LdyljffccWiuNFR51/BJHAZIqUDw3LsrdYWzg
# g4x06tgMvOEf0nITelpFTxqVvMtJhnOfZbpdXZQ5o1TspxfTEVOQAsp05HUNCXyh
# znlVLr0JaNkM7edgk59zmdTbSGdMq8Ztuu6VyrivOlMSPWmay5MjvwTzuNorbwBv
# 0DL+7cyZBp7NYZou+DoGd1lFZN0jU5IsQKgm3+00pnnJ67crdFwfz/8bq3MhTiKO
# WEb04FT3OZVp+jzvaChHWLQ8gbCORgClaZq1H3aqI7JeRkWEEEp6Tv4WAVsr/i7L
# oXU72gOb8CAzPFqwI4Excdrxp0I4OXbECHlDqU4sTInqwlMwofmxeO4u94196qIq
# JQl+8Sykl06VktqMux84Iw3ZQLH08J8LaJ+WDUycc4OjY61I7FGxCDkbSQf3npXe
# RFm0IBn8GiW+TRDk6J2XJFLWEtVZmhboFlBLoUlqHUCKu0QOhU/+AEOqnY98j2zR
# MYICQzCCAj8CAQEwgZAwfDELMAkGA1UEBhMCVVMxCzAJBgNVBAgTAk1JMRIwEAYD
# VQQHEwlBbm4gQXJib3IxEjAQBgNVBAoTCUludGVybmV0MjERMA8GA1UECxMISW5D
# b21tb24xJTAjBgNVBAMTHEluQ29tbW9uIFJTQSBDb2RlIFNpZ25pbmcgQ0ECEAcD
# cdEPeVpAcZkrlAdim+IwDQYJYIZIAWUDBAIBBQCggYQwGAYKKwYBBAGCNwIBDDEK
# MAigAoAAoQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3
# AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgalOD4jtMCfiUJ2zM
# Bi+sUcC6s3RsyGcA7LgMYfmTMQ4wDQYJKoZIhvcNAQEBBQAEggEAGLbs4Br6TIJJ
# /gCmdiPWUUc7CHxALVW2x/lCWkdTR3EPCEXipgjtMwiwePW8yPZL5a3xHq1hJSYH
# lfqdS6eFfGhE6AaQDUffsLzSsNgBLMa5WX+AnJes7gqO07lg4jMM/tvb/3TN2s3X
# cjuVomcdBu+dw8N8b9pOIXcDKV+j1W5h3xsYMz9/0HTzPVaVcmu+oDSkcPZfPM66
# CUGFuRkGkgj0fJvaWpnpm5ife5M5l50h5t+XaKJwBA9ncWO2Al5nbrYm7Ey5trxM
# iRTs4HJXqbO8GiLpuTCNJn3sR0r8VKyMf9nELsg4o9Sm0JmrRI6/qxXzUeoA51wr
# 05Oe1xuHIQ==
# SIG # End signature block
