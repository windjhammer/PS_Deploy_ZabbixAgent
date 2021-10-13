<#
# CITRA IT CONSULTING
# SCRIPT PARA INSTALAÇÃO AUTOMÁTICA DO AGENTE ZABBIX
# Author: luciano@citrait.com.br
# Date: 19/08/2020
# version: 1.0
#
# Versão homologada: zabbix_agent-5.0.16-windows-amd64
#>
#Requires -Version 5 




# Default install path
$ZABBIX_INSTALL_DIR = 'C:\zabbix'

# Zabbix server / proxy address
$ZABBIX_SERVER = "172.16.2.1"


# Zabbix download URL
$download_url = 'https://cdn.zabbix.com/zabbix/binaries/stable/5.0/5.0.16/zabbix_agent-5.0.16-windows-amd64.zip'


#-------------------------------------------------------------------------------------------------------------------
# Do not modify from this line below
#-------------------------------------------------------------------------------------------------------------------

# Adicionando o assembly c# do módulo de Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem


# Logging function
Function Log
{
	Param([String]$text)
	$timestamp = Get-Date -Format F
	Write-Host -ForegroundColor Green "$timestamp`: $text"
	
}

# Error Log Function
Function LogError
{
	Param([String]$text)
	$timestamp = Get-Date -Format F
	Write-Host -ForegroundColor Red "$timestamp`: $text"	
}


# Get the path of running zabbix
Function GetRunningZabbixPath
{
	$ErrorActionPreferenceDefault = $ErrorActionPreference
	$ErrorActionPreference = "SilentlyContinue"
	$zabbix_process = Get-Process "zabbix_agentd"
	If($zabbix_process -eq $null)
	{
		Throw "Old Zabbix process not found. Is it really running?"
	}
	$ErrorActionPreference = $ErrorActionPreferenceDefault
	Return $zabbix_process.Path
}


# Remove Zabbix From Current System
Function UninstallZabbix
{
	Param([String]$Zabbix_Agent_Path)
	
	# Validate if executable path is correct
	If([System.IO.File]::Exists($Zabbix_Agent_Path))
	{
		
		$zabbix_current_install_path = Split-Path -Parent $Zabbix_Agent_Path
		$zabbix_current_config_path = Join-Path -Path $zabbix_current_install_path -ChildPath "zabbix_agentd.conf"
		UninstallZabbixService $Zabbix_Agent_Path $zabbix_current_config_path
		start-sleep 3
		
		If(IsZabbixRunning)
		{
			LogError("Error uninstalling old zabbix version. Uninstall it manually!")
			Return $false
		}else{
			Log("Old Zabbix installation successfully removed !!")
			Return $true
		}
	}Else{
		LogError("Old zabbix installation path not found! Remove it manually !")
	}
}

# Tell if zabbix process is running
Function IsZabbixRunning
{
	$ErrorActionPreferenceDefault = $ErrorActionPreference
	$ErrorActionPreference = "SilentlyContinue"
	$zabbix_process = Get-Process "zabbix_agentd"
	$ErrorActionPreference = $ErrorActionPreferenceDefault
	Return ($zabbix_process -ne $null)
	
}


# Detects and remove zabbix actually running
Function UninstallCurrentZabbix
{
	If(IsZabbixRunning)
	{
		Log("Found old zabbix installation. trying to remove it prior.")
		try{
			$running_zabbix_path = GetRunningZabbixPath
			UninstallZabbix $running_zabbix_path
		}catch{
			LogError("Error removing Zabbix")
			LogError($_.Exception)
			Exit(0)
		}
	}else{
		LogError("Zabbix not running. Nothing to remove...")
	}
	
}




# Downloads Zabbix from a given url
Function DownloadZabbix
{
	Param(
		[String]$zabbix_agent_url_download, 
		[String]$dir_to_save
	)
	
	try{
		$webclient = New-Object System.Net.WebClient
		$zabbix_agent_uri = New-Object System.URI $zabbix_agent_url_download
		$zabbix_download_filename = $zabbix_agent_uri.segments[-1]
		$DestinationDownloadFile = Join-Path -Path $dir_to_save -ChildPath $zabbix_download_filename
		$webclient.DownloadFile($zabbix_agent_uri, $DestinationDownloadFile)
		Return $DestinationDownloadFile
	}catch{
		LogError("Error Downloading Zabbix")
		Throw $_.Exception
	}
	
	
}


# Extract a downloaded zabbix agent zip packaged
Function ExtractZabbixDownload
{
	Param(
		[String] $source_zipfile,
		[String] $destination_directory
	)
	
	Log("Decompressing file $source_zipfile to $destination_directory")
	
	# Check if destination directory already exists
	If([System.IO.Directory]::Exists($destination_directory))
	{
		# Delete It
		try{
			[System.IO.Directory]::Delete($destination_directory, $true)
		}catch{
			LogError("Could not remove temporary installer previous directory. Remove it manually and run the script again!")
			Exit(0)
		}
	}
	try{
		[System.IO.Compression.ZipFile]::ExtractToDirectory($source_zipfile, $destination_directory)
	}catch{
		LogError("Error decompressing the zabbix installer zip file")
		LogError($_.Exception)
		Exit(0)
	}
	
}



# Install the zabbix service
Function InstallZabbixService
{
	Param(
		[String] $zabbix_agentd_path,
		[String] $zabbix_conf_file
	)
	
	&$zabbix_agentd_path -c $zabbix_conf_file -i
	&$zabbix_agentd_path -c $zabbix_conf_file -s
	
}


# Uninstall the zabbix service
Function UninstallZabbixService
{
	Param(
		[String] $zabbix_agentd_path,
		[String] $zabbix_conf_file
	)

	&$zabbix_agentd_path -c $zabbix_conf_file -x
	&$zabbix_agentd_path -c $zabbix_conf_file -d
	
}



# Set's up the zabbix configuration file parameters
Function SetupZabbixConfFile
{
	Param(
		[String] $conf_file_path
	)
	
	# Checking if inside active directory
	$MachineDomain = (Get-ItemProperty -path  hklm:\System\currentcontrolset\services\tcpip\parameters).Domain
	$this_host_fqdn = ""
	If(-Not [String]::IsNullOrEmpty($MachineDomain))
	{
		# Domain member
		$this_host_fqdn = [String]::Concat($env:computername, ".", $MachineDomain)
	}Else{
		# Not in ActiveDirectory
		$this_host_fqdn = $env:computername
	}
	
	# Reading entire confi file into memory
	# !! it reads into a object[] not a string !!
	$zabbix_config_data = Get-Content -Path $conf_file_path -Encoding UTF8
	
	
	# Modifying Log Directive
	$server_config_index = $zabbix_config_data.IndexOf("LogFile=c:\zabbix_agentd.log")
	$zabbix_config_data[$server_config_index] = "LogFile=$ZABBIX_INSTALL_DIR\zabbix_agentd.log"
	
	# Modifying Server directive
	$server_config_index = $zabbix_config_data.IndexOf("Server=127.0.0.1")
	$zabbix_config_data[$server_config_index] = "Server=$ZABBIX_SERVER"
	
	# Modifying ServerActive directive
	$server_config_index = $zabbix_config_data.IndexOf("ServerActive=127.0.0.1")
	$zabbix_config_data[$server_config_index] = "ServerActive=$ZABBIX_SERVER"
	
	# Modifying Hostname directive
	$server_config_index = $zabbix_config_data.IndexOf("Hostname=Windows host")
	$zabbix_config_data[$server_config_index] = "Hostname=$this_host_fqdn"
	
	
	# Generate outputed configuration file
	[System.IO.File]::Delete($conf_file_path)
	
	# Hack to create a file without BOM (byte order marker). Defaults powershell breaks zabbix (utf8 without bom)
	New-Item -Type File -Path $conf_file_path | Out-Null
	ForEach($line in $zabbix_config_data)
	{
		If($line.StartsWith('#') -or [String]::IsNullOrEmpty($line))
		{
			# skip line, do not add if it's a comment or blank line.
		}else{
			Add-Content -Path $conf_file_path -Value $line
		}
	}
	
	
}


# Copy files from source install dir to destination installation directory
Function CopyZabbixSetupFiles
{
	Param(
		[String] $setup_source_dir,
		[String] $setup_destination_dir
	)
	
	$agentd_exe_path = Join-Path -Path $setup_destination_dir -ChildPath "zabbix_agentd.exe"
	[System.IO.File]::Copy("$setup_source_dir\bin\zabbix_agentd.exe", $agentd_exe_path)
	
	# Copying zabbix_get.exe
	# zabbix_get.exe
	$get_exe_path = Join-Path -Path $setup_destination_dir -ChildPath "zabbix_get.exe"
	[System.IO.File]::Copy("$setup_source_dir\bin\zabbix_get.exe", $get_exe_path)
	
	# Copying zabbix_sender.exe
	# zabbix_sender.exe
	$sender_exe_path = Join-Path -Path $setup_destination_dir -ChildPath "zabbix_sender.exe"
	[System.IO.File]::Copy("$setup_source_dir\bin\zabbix_sender.exe", $sender_exe_path)
	
	
	# Copying zabbix_agentd.conf
	# zabbix_agentd.conf
	$zabbix_conf_path = Join-Path -Path $setup_destination_dir -ChildPath "zabbix_agentd.conf"
	[System.IO.File]::Copy("$setup_source_dir\conf\zabbix_agentd.conf", $zabbix_conf_path)
	
}



# Creates the firewall fules necessary	
Function CreateZabbixFirewallRules
{
	Param(
		[String] $zabbix_agentd_path,
		[String] $zabbix_server
	)
	
	# Removing old rules
	Get-NetFirewallRule | Where-Object{$_.DisplayName -match 'Zabbix'} | ForEach-Object{ Remove-NetFirewallRule $_ }
	
	# Creating the apropriate rule
	try{
		New-NetFirewallRule -DisplayName "Zabbix Agent (TCP-In)" -Direction Inbound -Program $zabbix_agentd_path -RemoteAddress $zabbix_server -Action Allow | Out-Null
	}catch{
		Throw $_.Exception
	}
}







#-------------------------------------------------------------------------------------------------------------------
# MAIN SCRIPT ENTRY
#-------------------------------------------------------------------------------------------------------------------
Log("------====   DEPLOYING ZABBIX ====-------")
# Download zabbix agent
Log("Working from temporary folder")
Set-Location -Path $env:tmp

# Is it already running?
If(IsZabbixRunning)
{
	# Uninstall It
	LogError("Zabbix already running, removing it first !")
	UninstallCurrentZabbix
}
	
# Download new version
Log("Downloading zabbix agent installer")
$zabbix_installer_zip_file = DownloadZabbix $download_url $pwd

# Extract it
Log("Extracting the zip installer")
$installer_path = $zabbix_installer_zip_file.replace(".zip","")
ExtractZabbixDownload $zabbix_installer_zip_file $installer_path

# Removing the installation dir if it exists
If([System.IO.Directory]::Exists($ZABBIX_INSTALL_DIR))
{
	[System.IO.Directory]::Delete($ZABBIX_INSTALL_DIR, $true) | Out-Null
}

# Create the installation dir
Log("Creating destination install directory $ZABBIX_INSTALL_DIR")
[System.IO.Directory]::CreateDirectory($ZABBIX_INSTALL_DIR) | Out-Null

# Copy zabbix files
Log("Copying zabbix files")
CopyZabbixSetupFiles $installer_path $ZABBIX_INSTALL_DIR

# Adjust zabbix config file
Log("Adjusting zabbix configuration file")
$zabbix_conf_file = Join-Path -Path $ZABBIX_INSTALL_DIR -ChildPath "zabbix_agentd.conf"
SetupZabbixConfFile $zabbix_conf_file


# Setup the service and start it
Log("Setup and start zabbix services...")
$zabbix_agentd_file = Join-Path -Path $ZABBIX_INSTALL_DIR -ChildPath "zabbix_agentd.exe"
InstallZabbixService $zabbix_agentd_file $zabbix_conf_file


# Setup Firewall Rule to allow zabbix agent exchange information with server/proxy
Log("Creating firewall rule for zabbix_agentd.exe")
CreateZabbixFirewallRules $zabbix_agentd_file $ZABBIX_SERVER


# CleanUp
# delete temporary installation folder
Log("Clean up time !!")
[System.IO.Directory]::Delete($installer_path, $true) | Out-Null
[System.IO.File]::Delete($zabbix_installer_zip_file)

Log("Process Finished !!")


