<#TODO:

#>
Param (
	[Switch]$Load
)
If (!$Load) {
	Write-Host ""
	Write-Host "To load this library into your current frame, place it in the same directory that the script is run from (or make a"
	Write-Host "symlink to it) and then execute this command in your script:"
	Write-Host '	. "$PSScriptRoot\PSLibrary.ps1" -Load'
	Write-Host ""
	Write-Host "To create a shortcut to run a powershell script, create the shortcut using the following format:"
	Write-Host "	powershell -executionpolicy bypass -command ""&'<path_to_script>' <parameters>"""
	Write-Host ""
	Pause
	Return
}

Function Validate-HostName {
	<#
		Verify that a string is a valid hostname
	#>
	Param (
		#Take one argument - the string to check
		[String]$HostName
	)

	#If the host name ends with a ., remove it
	If ($HostName -match "\.$") {
		$HostName = $HostName.Remove($HostName.Length - 1)
	}

	#If the hostname is 0 characters or >255 characters, fail
	If (($HostName.Length -lt 1) -or ($HostName.Length -gt 255)) {
		Return $False
	}

	#Set the output to default to true
	$Out = $True
	#Iterate through each label
	$HostName.Split(".").ForEach({
		#If the label is >63 characters, or doesn't start and end with an alphanumeric, or includes characters which are not alphanumeric or hyphen, fail
		If (($_.Length -gt 63) -or !($_ -match "^([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])$")) {
			#Update the output
			$Out = $False
			#Break the for loop early (break ends the whole function)
			Return
		}
	})

	#Return whether or not the string is a valid hostname
	Return $Out
}

Function Validate-IPAddress {
	<#
		Verify that a string is a valid IP address
	#>
	Param (
		#Take one argument - the IP to check
		[String]$IPAddress
	)

	#If the string isn't comprised of exactly 4 octets, fail
	If (!($IPAddress -match "^(\d{1,3}\.){3}\d{1,3}$")) {
		Return $False
	}

	#Set the output to default to true
	$Out = $True
	#Iterate through each octet
	$IPAddress.Split(".").ForEach({
		#If the octet is greater than 255, fail
		If ([Int]$_ -gt 255) {
			#Update the output
			$Out = $False
			#Break the loop early (break ends the whole function)
			Return
		}
	})

	#Return whether or not the string is a valid IP
	Return $Out
}

Function Wait-Connect {
	<#
		Wait for a connection to a specified server.  Return true when the connection is established or false if it times out.
		This function has 3 parameters:
			1. The name or IP address of the resource to establish a conneciton to.  This is mandatory with no default
			2. The number of seconds to wait between attempts.  Mandatory with a default of 10
			3. The number of seconds after which to abort connecting.  Mandatory with a default of 300 (5 min)

		Specify the resource using -IP to specify that it's an IP address for more stringent requirements
	#>
	#This defaults the parameter set to "Host".  They can force it into "Array" by providing an array
	[CmdletBinding(DefaultParameterSetName='Host')]
	#Parameter declaration
	Param (
		#Take an array positionally as the first argument in the "Array" set
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="Array")]
		#Only accept 1-3 arguments
		[ValidateCount(1,3)]
		[Array]$ParamArray,

		#Take a required string positionally as the first argument in the "Host" set
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="Host")]
		#Can be provided with the name ResourceName, Resource, Name, or Dest
		[Alias("Resource","Name","Dest")]
		[ValidateScript({Validate-HostName $_})]
		[String]$ResourceName,

		#Take a required string positionally as the first argument in the "IP" set
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="IP")]
		#Can be provided with the name IPAddress, DestIP, or IP
		[Alias("DestIP","IP")]
		[ValidateScript({Validate-IPAddress $_})]
		[String]$IPAddress,

		#Take an integer positionally as the second argument in the "Host" set, the "IP" set, and the "Array" set
		[Parameter(Position=1, ParameterSetName="Host")]
		[Parameter(Position=1, ParameterSetName="IP")]
		[Parameter(Position=1, ParameterSetName="Array")]
		#Can be provided with the name WaitTime, Wait, or Time
		[Alias("Wait","Time")]
		#Default to 10 seconds
		[Timespan]$WaitTime = [Timespan]::FromSeconds(10),

		#Take an integer positionally as the third argument in the "Host" set, the "IP" set, and the "Array" set
		[Parameter(Position=2, ParameterSetName="Host")]
		[Parameter(Position=2, ParameterSetName="IP")]
		[Parameter(Position=2, ParameterSetName="Array")]
		#Default to 5 minutes
		[Timespan]$Timeout = [Timespan]::FromMinutes(5)
	)

	#If the parameter array was provided
	If ($PSCmdlet.ParameterSetName -eq "Array") {
		#Iterate through the items in the array
		$ParamArray.ForEach({
			#If the item is a string
			If ($_ -is "String") {
				#If there's no resource name yet
				If ([String]::IsNullOrEmpty($ResourceName)){
					#If the item is a valid IP or host name, store it in the resource name
					If ((Validate-IPAddress $_) -or (Validate-HostName $_)) {
						$ResourceName = $_
					#Otherwise, throw an error due to invalid input
					} Else {
						Throw "Invalid arguments specified!"
					}
				#Otherwise, throw an error due to invalid input
				} Else {
					Throw "Invalid arguments specified!"
				}
			#If it's anything Else, throw an error due to invalid input
			} Else {
				Throw "Invalid arguments specified!"
			}
		})
		#If there's no resource name, throw an error
		If ([String]::IsNullOrEmpty($ResourceName)) {Throw "No resource name specified!"}
	#If the IP address was specified, store it in the resource name
	} ElseIf ($PSCmdlet.ParameterSetName -eq "IP") {
		$ResourceName = $IPAddress
	}

	#Start a timer
	$Timer = [Diagnostics.Stopwatch]::StartNew()
	#Set the output flag to true
	[Bool]$Out = $True

	#While we cannot establish a connection to the $ResourceName (one ping in quiet mode)
	While (-Not (Test-Connection -ComputerName $ResourceName -Quiet -Count 1)) {
		#If the time elapsed has exceeded the timeout
		If ($Timer.Elapsed -ge $Timeout) {
			#Set the output flag to false
			$Out = $False
			#Break out of the While loop
			Break
		}
		#Sleep for $WaitTime seconds
		Start-Sleep -MilliSeconds $WaitTime.TotalMilliseconds
	}

	#Stop the timer
	$Timer.Stop()

	#Return the output flag
	Return $Out
}

Function Start-VPNProcess {
	<#
		Start a process in a specific directory, after waiting for a specified VPN resource to become available.  Optionally, run as administrator and write output indicating what's happening
		This function has up to 6 parameters, in two sets:
			1. The path to the *.exe to be started.  If not provided, it will prompt for input.  This is in both parameter sets
			2. The path in which to start the process.  If not provided, it will prompt for input.  This is in both parameter sets
			3. The resource to wait for which indicates VPN connectivity
			4. A switch to run the process as an administrator.  This is in both parameter sets
			5. A switch to turn on written output.  This is only in the "Write" parameter set
			6. The display name of the process to be started.  This is only in the "Write" parameter set and is mandatory
		The function will default to the "None" parameter set, but can be forced into the "Write" parameter set by including either the WriteOut flag or a ProcessName parameter.  However, including a process name with no WriteOut flag won't do anything
	#>
	#This defaults the parameter set to "None".  They can force it into "Array" or "Write" by providing an array or one of the write parameters
	[CmdletBinding(DefaultParameterSetName='None')]
	#Parameter declaration
	Param (
		#Take an array positionally as the first argument in the "Array" set
		[Parameter(Position=0, Mandatory=$True, ParameterSetName="Array")]
		#Only accept 3-8 arguments
		[ValidateCount(3,8)]
		[Array]$ParamArray,

		#Take a required string as the first argument in the "None" and "Write" sets
		[Parameter(Position=0, Mandatory=$True, ParameterSetName="None")]
		[Parameter(Position=0, Mandatory=$True, ParameterSetName="Write")]
		#Can be provided using the name TargetProcess, FileName, File, or EXE
		[Alias("FileName","File","EXE")]
		#Use the following script to validate the input
		[ValidateScript({
			#Verify that it's a path that exists and it's not a directory (it's a file)
			If ((Test-Path $_) -and -not ((Get-Item $_) -is [IO.DirectoryInfo])) {
				Return $True
			#If it's not valid, throw an error
			} Else {
				Throw "Invalid process specified!"
			}
		})]
		[String]$TargetProcess,

		#Take a required string as the second argument in the "None" and "Write" sets
		[Parameter(Position=1, Mandatory=$True, ParameterSetName="None")]
		[Parameter(Position=1, Mandatory=$True, ParameterSetName="Write")]
		#Can be provided using the name StartDirectory, WorkingDirectory, Directory, or Dir
		[Alias("WorkingDirectory","Directory","Dir")]
		#Use the following script to validate the input
		[ValidateScript({
			#Verify that it's a path that exists and it's a directory
			If ((Test-Path $_) -and ((Get-Item $_) -is [IO.DirectoryInfo])) {
				Return $True
			#If it's not valid, throw an error
			} Else {
				Throw "Invalid start path specified!"
			}
		})]
		[String]$StartDirectory,

		#Take a required string as the third argument in the "None" and "Write" sets
		[Parameter(Position=2, Mandatory=$True, ParameterSetName="None")]
		[Parameter(Position=2, Mandatory=$True, ParameterSetName="Write")]
		#Can be provided using the name VPNResource, Resource, WaitFor, or VPN
		[Alias("Resource","WaitFor","VPN")]
		[String]$VPNResource,

		#Take the As Admin flag in the "None" and "Write" sets
		[Parameter(ParameterSetName="None")]
		[Parameter(ParameterSetName="Write")]
		#Can be provided using the name AsAdmin, Admin, or ADM
		[Alias("Admin","ADM")]
		[Switch]$AsAdmin,

		#Take the Write Out flag in the "Write" set
		[Parameter(ParameterSetName="Write")]
		#Can be provided using the name WriteOut or Write
		[Alias("Write")]
		[Switch]$WriteOut,

		#Take a required string as the 4th parameter in the "Write" set
		[Parameter(ParameterSetName="Write", Mandatory=$True, Position=3)]
		#Can be provided using the name ProcessName or Name
		[Alias("Name")]
		[String]$ProcessName,

		#Take an integer as the 4th parameter in the "None" set or the 5th in the "Write" set, or the second in the "Array" set
		[Parameter(Position=3, ParameterSetName="None")]
		[Parameter(Position=4, ParameterSetName="Write")]
		[Parameter(Position=1, ParameterSetName="Array")]
		#Can be provided using the name WaitTime or CheckTime
		[Alias("CheckTime")]
		#Default to 10 seconds
		[Timespan]$WaitTime = [Timespan]::FromSeconds(10),

		#Take an integer as the 5th parameter in the "None" set or the 6th in the "Write" set, or the third in the "Array" set
		[Parameter(Position=4, ParameterSetName="None")]
		[Parameter(Position=5, ParameterSetName="Write")]
		[Parameter(Position=2, ParameterSetName="Array")]
		#Default to 5 minutes
		[Timespan]$Timeout = [Timespan]::FromMinutes(5),

		#Take an exclusive flag in the "None" and "Write" sets
		[Parameter(ParameterSetName="None")]
		[Parameter(ParameterSetName="Write")]
		#Can be provided using the name Exclusive or Exc
		[Alias("Exc")]
		[Switch]$Exclusive
	)

	#If the parameter array was provided
	If ($PSCmdlet.ParameterSetName -eq "Array") {
		#Iterate through the items in the array
		$ParamArray.ForEach({
			#If the item is a string
			If ($_ -is "String") {
				#If the item is one of the admin flags, set the AsAdmin flag
				If ($_ -in @("-Adm","-Admin","-AsAdmin")) {
					$AsAdmin = $True
				#If the item is one of the write flags, set the WriteOut flag
				} ElseIf ($_ -in @("-Write", "-WriteOut")) {
					$WriteOut = $True
				#If the item is one of the exclusive flags, set the exclusive flag
				} ElseIf ($_ -in @("-Exc","-Exclusive")) {
					$Exclusive  = $True
				#Otherwise
				} Else {
					#If there's no target process and the item is a path that exists and the item is not a directory
					If (([String]::IsNullOrEmpty($TargetProcess)) -and (Test-Path $_) -and -not ((Get-Item $_) -is [IO.DirectoryInfo])) {
						#Set it in the target process
						$TargetProcess = $_
					#If there's no start directory and the item is a path that exists and it's a directory
					} ElseIf (([String]::IsNullOrEmpty($StartDirectory)) -and (Test-Path $_) -and ((Get-Item $_) -is [IO.DirectoryInfo])) {
						#Set it in the start directory
						$StartDirectory = $_
					#If there's no VPN resource
					} ElseIf ([String]::IsNullOrEmpty($VPNResource)) {
						#Set the item in the VPN resource
						$VPNResource = $_
					#If there's no process name
					} ElseIf ([String]::IsNullOrEmpty($ProcessName)) {
						#Set the item in the process name
						$ProcessName = $_
					#Otherwise, throw an error due to invalid input
					} Else {
						Throw "Invalid arguments specified!"
					}
				}
			#If it's not a string but it's an int
			} Else {
				Throw "Invalid arguments specified!"
			}
		})

		#If there's no target process, throw an error
		If ([String]::IsNullOrEmpty($TargetProcess)) {Throw "No target process specified!"}
		#If there's no start directory, throw an error
		If ([String]::IsNullOrEmpty($StartDirectory)) {Throw "No starting directory specified!"}
		#If there's no VPN resource, throw an error
		If ([String]::IsNullOrEmpty($VPNResource)) {Throw "No VPN resource specified!"}
		#If there's no process name and the write flag is set, throw an error
		If ([String]::IsNullOrEmpty($ProcessName) -and $WriteOut) {Throw "No display name specified for the target process!"}
	}

	#If the AsAdmin flag is set
	If ($AsAdmin) {
		#Set the run verb to "RunAs"
		[String]$RunVerb = "RunAs"
	} Else {
		#Otherwise, set it to "Open"
		[String]$RunVerb = "Open"
	}

	#If the write flag is set
	If ($WriteOut) {
		#Write that we're waiting for a connection
		Write-Output "Waiting for connection via VPN..."
	}

	#Use the wait-connect function to wait for a connection to the VPN resource
	If (Wait-Connect $VPNResource -WaitTime $WaitTime -Timeout $Timeout) {
		#If the write flag is set
		If ($WriteOut) {
			#Write that the connection is established and the process is being started
			Write-Output "Connection established."
			Write-Output "Starting $ProcessName executable..."
		}
		#See if the process is already running
		$ProcVar = Get-Process -ErrorAction SilentlyContinue -Name $([IO.Path]::GetFilenameWithoutExtension($TargetProcess))
		#If the process is already running and the exclusive flag was provided
		If ($ProcVar -and $Exclusive) {
			#If the write flag is set, alert the user
			If ($WriteOut) {
				Write-Output "$ProcessName process is already running!"
			}
		} Else {
			#Otherwise, start the appropriate process in the appropriate directory with the appropriate flag.  Store the process in $ProcVar
			$ProcVar = Start-Process -Verb $RunVerb -WorkingDirectory $StartDirectory -FilePath $TargetProcess -PassThru
			#If the write flag is set
			If ($WriteOut) {
				#Write that the process has been started
				Write-Output "$ProcessName executable started."
			}
		}
		#Return a true value
		Return $ProcVar
	#If the wait-connect timed out
	} Else {
		#If the write flag is set
		If ($WriteOut) {
			#Write that the connection failed
			Write-Output "Unable to connect via VPN.  Aborting starting $ProcessName executable."
		}
		#Return false
		Return $False
	}
}

Function New-PromptOption {
	<#
		Create an option to be used in an option array for user prompts
		This function has 2 parameters:
			1. The name of the option to be displayed
			2. The description of the option, which will be displayed if the user asks for help
	#>
	#This defaults the parameter set to "None".  They can force it into "Array" by providing an array
	[CmdletBinding(DefaultParameterSetName="None")]
	#Parameter declaration
	Param (
		#Take an array positionally as the first argument in the "Array" set
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="Array")]
		#Only take 2 arguments
		[ValidateCount(2,2)]
		[String[]]$ParamArray,

		#Take a required string as the first argument in the "None" set
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="None")]
		#Can be provided using the name Option, Opt, or O
		[Alias("Opt","O")]
		[String]$Option,

		#Take a required string as the second argument in the "None" set
		[Parameter(Mandatory=$True, Position=1, ParameterSetName="None")]
		#Can be provided using the name Description, Desc, or D
		[Alias("Desc","D")]
		[String]$Description
	)

	#If the parameter array was provided
	If ($PSCmdlet.ParameterSetName -eq "Array") {
		#Store the first argument as the option
		$Option = $ParamArray[0]
		#Store the second argument as the description
		$Description = $ParamArray[1]
	}

	#Return an object for the desired option and description
	Return New-Object Management.Automation.Host.ChoiceDescription $Option, $Description
}

Function New-OptionArray {
	<#
		Create an array of the provided options to be used in a user prompt
		$($Args) is used so that $Args is treated the same way whether the user provides a comma between options or not
	#>
	Return [Management.Automation.Host.ChoiceDescription[]]$($Args)
}

Function Select-Option {
	<#
		Provide the user with a Yes/No prompt with the provided title and message.  Options are 0-indexed.  Default to option 0 if no default is specified
		This function has 4 parameters:
			1. The title (the message to display before the question)
			2. The message (the question to be asked of the user)
			3. An array of options.  Defaults to Yes / No
			4. The option to default to (0-indexed).  Defaults to option 0
		Optionally, the prompt can be timed.  In timed mode, three additional parameters are available:
			5. The timeout for the prompt
			6. The minimum time to wait after the user has pressed a key
			7. The interval after which to check for keys
	#>
	[CmdletBinding(DefaultParameterSetName='None')]
	#Parameter declaration
	Param (
		#Take a required string as the first parameter in the "None" and "Timed" option sets
		[Parameter(Mandatory=$True, Position=0, ParameterSetName='None')]
		[Parameter(Mandatory=$True, Position=0, ParameterSetName='Timed')]
		#Can be provided using the name PromptTitle, Title, or T
		[Alias("Title","T")]
		[String]$PromptTitle,

		#Take a required string as the second parameter in the "None" and "Timed" option sets
		[Parameter(Mandatory=$True, Position=1, ParameterSetName='None')]
		[Parameter(Mandatory=$True, Position=1, ParameterSetName='Timed')]
		#Can be provided using the name PromptQuestion, Question, Message, or Q
		[Alias("Question","Message","Q")]
		[String]$PromptQuestion,

		#Take an array as the third parameter in the "None" and "Timed" option sets
		[Parameter(Position=2, ParameterSetName='None')]
		[Parameter(Position=2, ParameterSetName='Timed')]
		#Can be provided using the name OptionList, Options, Opts, or O
		[Alias("Options","Opts","O")]
		[Array]$OptionList = $(
			New-OptionArray $(New-PromptOption "&Yes" "Message indicating what ""Yes"" will do") $(New-PromptOption "&No" "Message indicating what ""No"" will do")
		),

		#Take an integer as the fourth parameter in the "None" and "Timed" option sets
		[Parameter(Position=3, ParameterSetName='None')]
		[Parameter(Position=3, ParameterSetName='Timed')]
		#Can be provided using the name DefaultOption, Default, Def, or D
		[Alias("Default","Def","D")]
		#Default to 0
		[Int]$DefaultOption = 0,

		#Take a timespan as the fifth parameter in the "Timed" option set
		[Parameter(Position=4, ParameterSetName='Timed')]
		#Default to a timeout of 10 seconds
		[Timespan]$Timeout = [Timespan]::FromSeconds(10),
		
		#Take a timespan as the sixth parameter in the "Timed" option set
		[Parameter(Position=5, ParameterSetName='Timed')]
		#Default of a timeout of 1 second after pressing a key
		[Timespan]$KeyDelay = [Timespan]::FromSeconds(1),
		
		#Take a timespan as the seventh parameter in the "Timed" option set
		[Parameter(Position=6, ParameterSetName='Timed')]
		#Default to checking for keys every 1/10th of a second (100 ms)
		[Timespan]$CheckInt = [Timespan]::FromMilliseconds(100),
		
		#Take a switch parameter in the "Timed" option set, for easy switching to timed mode
		[Parameter(ParameterSetName='Timed')]
		[Switch]$Timed
	)

	#If not in the timed parameter set, use $Host.UI.PromptForChoice for a prompt with no timeout
	If (!$Timed) {
		#This function is essentially a macro.  Run the command to prompt the user given the provided options and Return the output.
		Return $Host.UI.PromptForChoice( $PromptTitle, $PromptQuestion, $OptionList, $DefaultOption )
	} Else {
		#Create a function to write the prompt text, with the default option in yellow
		Function Write-Prompt {
			Param(
				#Take an array of strings to write
				[String[]]$Pstr,
				#And a switch to avoid writing a newline afterwards
				[Switch] $NoNewLine
			)

			#Write the first element in the array in white (before the default)
			If ([bool]$Pstr[0]) {
				Write-Host -NoNewLine $Pstr[0]
			}
			#Write the second element in the array (the default) in yellow
			Write-Host -NoNewLine -ForegroundColor Yellow $Pstr[1]
			#Then write the last element in the array in white (after the default)
			#If the NoNewLine parameter was provided, don't write a newline afterwards
			Write-Host -NoNewLine:$NoNewLine $Pstr[2]
		}

		If ($DefaultOption -ge $OptionList.Length) {
			#Re-run in un-timed mode to throw the correct error
			Return Select-Option $PromptTitle $PromptQuestion $OptionList $DefaultOption
		}
		
		#Write a newline
		Write-Host ""
		#Write the title
		Write-Host $PromptTitle
		#Write the question
		Write-Host $PromptQuestion
		
		#Create an empty hashtable to hold valid inputs
		$Map = @{}
		#Create a new arraylist for an array-like object which can easily be appended to
		$Disp = New-Object System.Collections.ArrayList
		#Create a 3-element array to hold the prompt string
		#Use arraylists for performance when appending elements
		$Pstr = @($(New-Object System.Collections.ArrayList),$(New-Object System.Collections.ArrayList),$(New-Object System.Collections.ArrayList))
		#Start indexing at 0
		$Index = 0
		#Iterate through the provided option list
		ForEach ($Item in $OptionList) {
			#Strip ampersands from the item label for the long input
			$Long = $Item.Label.Replace("&","")
			#Short input is null for now
			$Short = ""
			#If the label contains an ampersand
			If ($Item.Label.Contains("&")) {
				#The short label is the caracter after the ampersand
				$Short = [String]$Item.Label[$Item.Label.IndexOf("&") + 1]
				#Map the short label to the index number
				$Map[$Short] = $Index
				#Add the short label with the help message to the help array
				#Have to store the output to consume it
				$Null = $Disp.Add(@($Short, $Item.HelpMessage))
			} Else {
				#If no ampersand, add the long label and the help message to the help array
				$Null = $Disp.Add(@($Long, $Item.HelpMessage))
			}
			#If the index is less than the default, add the option to the pre-default element in the prompt string array
			#If the index is greater than the default, add the option to the post-default element
			#And if the index is equal to the default, add the option to the default element
			$Null = $Pstr[(($Index -ge $DefaultOption) + ($Index -gt $DefaultOption))].add("[$Short] $Long")
			#Map the long label to the index number and increment the index number
			$Map[$Long] = $Index++
		}
		#If the default option contains an ampersand
		If ($OptionList[$DefaultOption].Label.Contains("&")) {
			#Store the short label as the default option
			$DefOp = $OptionList[$DefaultOption].Label[$OptionList[$DefaultOption].Label.IndexOf("&") + 1]
		} Else {
			#Otherwise, store the long label
			$DefOp = $OptionList[$DefaultOption].Label.Replace("&","")
		}
		#If ? is used as a key
		If ($Map.ContainsKey("?")) {
			#Re-run in un-timed mode to throw the correct error
			Return Select-Option $PromptTitle $PromptQuestion $OptionList $DefaultOption
		}
		#If first element isn't default, append a space
		If ($Pstr[0]) {
			$Null = $Pstr[0].Add(" ")
		}
		#Default option is always present
		$Null = $Pstr[1].Add(" ")
		#Append the help message to the post-default element in the prompt string array
		$Null = $Pstr[2].Add("[?] Help (default is ""$DefOp""): ")
		
		#And write the prompt string array (the options) with the default in yellow
		#Don't include a trailing newline
		Write-Prompt -NoNewLine $Pstr
		
		#Start a pair of timers
		$Timer = [Diagnostics.StopWatch]::StartNew()
		$Last = [Diagnostics.StopWatch]::StartNew()
		#Flush the input buffer
		$Host.UI.RawUI.FlushInputBuffer()
		#Start the input as an empty string
		$Inp = ""
		#As long as we haven't exceeded the timeout, or we've pressed a key recently enough
		While (($Timer.Elapsed -lt $Timeout) -or ($Last.Elapsed -lt $KeyDelay)) {
			#Check to see if there's a key available
			If ([Console]::KeyAvailable) {
				#If there is, grab the key but don't echo it
				$Key = [Console]::ReadKey($True)
				#If the key has a character and it's not a control character
				If ($Key.KeyChar -and ($Key.KeyChar -NotMatch "\p{C}")) {
					#Write the character
					Write-Host -NoNewLine $Key.KeyChar
					#Add the character to the input
					$Inp += [String]$Key.KeyChar
					#Restart the keystroke timer
					$Last.Restart()
				#If the key is a backspace
				} ElseIf (($Key.Key -eq "Backspace") -and ($Inp -ne '')){
					#Move the cursor back, overwrite the last character with a space, then move the cursor back again
					Write-Host -NoNewLine "$([Char]8) $([Char]8)"
					#Remove the last character from the input string
					$Inp = $Inp -Replace ".$"
					#Restart the keystroke timer
					$Last.Restart()
				#If the key is a carriage return
				} ElseIf ($Key.Key -eq "Enter") {
					#Write a newline
					Write-Host ""
					#If the input is exactly a question mark
					If ("?" -eq $Inp) {
						#Write out each of the help options stored earlier
						ForEach ($Option in $Disp) {
							Write-Host "$($Option[0]) - $($Option[1])"
						}
					#If the input is in the map
					} ElseIf ($Map.ContainsKey($Inp)) {
						#Return the index of the input
						Return $Map[$Inp]
					#If the input is null
					} ElseIf ('' -eq $Inp) {
						#Return the default index
						Return $DefaultOption
					#If the input isn't ?, isn't in the map, and isn't null
					}
					#Reset the input string
					$Inp = ""
					#Restart the timers
					$Timer.Restart()
					$Last.Restart()
					#Then re-write the prompt
					Write-Prompt -NoNewLine $Pstr
				}
			} Else {
				#If there's no key available, check back after the check interval
				Start-Sleep -Milliseconds $CheckInt.TotalMilliseconds
			}
		}
		#If the function has gotten this far, we've exceeded the timeout
		#Write a newline
		Write-Host ""
		#If they entered a valid key and just failed to hit enter, take that
		#Otherwise, return -1
		If ($Map.ContainsKey($Inp)) {
			Return $Map[$Inp]
		} Else {
			Return -1
		}
	}
}

Function Write-Update {
	<#
		This function first moves the cursor to the front of the current line, then writes the desired text, then wipes out any of the remaining contents of the line.
		It does not write a new line afterwards.  This makes it excellent for writing status updates
	#>
	#Parameter declaration
	Param(
		#Take one parameter, the text to be written
		#Take all parameters provided as the text
		[Parameter(ValueFromRemainingArguments=$True)]
		[String]$Text,

		#Take a flag to left-truncate the text
		[Alias("Truncate","Trunc", "LT")]
		[Switch]$LeftTruncate,

		#Take a flag to right-truncate the text
		[Alias("RTruncate","RTrunc","RT")]
		[Switch]$RightTruncate
	)

	#Get the current X position of the cursor
	[Int]$X = $Host.UI.RawUI.CursorPosition.X
	#Get the window width
	#The cursor never actually moves to the final position in the window, so subtract one to keep everything lined up
	[Int]$Width = $Host.UI.RawUI.WindowSize.Width-1
	#Instantiate an AfterText variable as null
	[String]$AfterText = ""

	#If the string is long enough that it will exceed the width
	If ($Text.Length -gt $Width) {
		#If the LeftTruncate flag is set
		If ($LeftTruncate) {
			#Get the substring starting at Length-Width characters (Keep $Width characters on the right)
			$Text = $Text.Substring($Text.Length-$Width)
		#Otherwise, if the RightTruncate flag is set
		} ElseIf ($RightTruncate) {
			#Remove all characters after the $Width
			$Text = $Text.Remove($Width)
		}
	}

	#If the text won't completely overwrite the previous contents of the line
	If ($X -gt $($Text.Length)) {
		<#
			Set the after text to a number of spaces equal to the difference, followed by a number of backspace characters equal to the difference

			$( " " * ($X-$Text.Length) ):
				$( ... )		- Treat the contents as an expression
				" "*( ... )	- a space character repated the specified number of times (the quotes don't need to be escaped because this text is being treated as an expression)
				$X - $Text.Length		- The number of characters between the end of the string and the previous cursor position

			$( [String][Char]8 * ($X-$Text.Length) ):
				$( ... )			- Treat the contents as an expression
				[String][Char]8		- Force the number 8 to a unicode character (this is the backspace character), and then to a string
				$( ... ) * ( ... )	- Repeat the string specified by the first expression the specified number of times
				$X - $Text.Length			- The number of characters between the end of the string and the previous cursor position
		#>
		$AfterText = "$(" "*($X-$Text.Length))$([String][Char]8*($X-$Text.Length))"
	}

	<#
		Without writing a new line afterwards, write backspace characters equal to the current X position (to get the cursor back to the beginning of the line), then write the input text, then write the AfterText we calculated (if any)

		$( [String][Char]8 * $X )$Text$AfterText:
			$( ... )			- Treat the contents as an expression
			[String][Char]8		- Force the number 8 to a unicode character (this is the backspace character), and then to a string
			$( ... ) * $X		- Repeat the specified string X times (write backspace characters to the beginning of the line)
			$Text				- The input text
			$AfterText			- The text contained in AfterText (nothing, or the spaces and backspace characters generated earlier)
	#>
	Write-Host -NoNewLine "$([String][Char]8*$X)$Text$AfterText"
}

Function Wait-ProcessRam {
	<#
		Wait for a process to hit a specified number of RAM handles.  Optionally restart it if it stalls at the same number of RAM handles for a specified period of time.  Optionally, it will wait for a process with the specified name to start
	#>
	#This defaults the parameter set to "Name".  They can force it into "Proc", "WriteName" or "WriteProc" by providing parameters included in one of these sets
	[CmdletBinding(DefaultParameterSetName="Name")]
	#Parameter declaration
	Param(
		#Take a string that's the name of the process to look for as the first parameter in the "Name", "WriteName", "NameRestart" and "WriteNameRestart" sets
		[Parameter(Position=0, Mandatory=$True, ParameterSetName="Name")]
		[Parameter(Position=0, Mandatory=$True, ParameterSetName="WriteName")]
		[Parameter(Position=0, Mandatory=$True, ParameterSetName="NameRestart")]
		[Parameter(Position=0, Mandatory=$True, ParameterSetName="WriteNameRestart")]
		[Alias("Name","PN")]
		[String]$ProcessName,

		#Take a process to wait for as the first parameter in the "Proc", "WriteProc", "ProcRestart", and "WriteProcRestart" sets
		[Parameter(Position=0, Mandatory=$True, ParameterSetName="Proc")]
		[Parameter(Position=0, Mandatory=$True, ParameterSetName="WriteProc")]
		[Parameter(Position=0, Mandatory=$True, ParameterSetName="ProcRestart")]
		[Parameter(Position=0, Mandatory=$True, ParameterSetName="WriteProcRestart")]
		[Alias("Proc")]
		[Diagnostics.Process]$Process,

		#Take an integer representing the RAM handles to wait for as the second parameter
		[Parameter(Position=1, Mandatory=$True)]
		[Alias("Handles","HandleCount")]
		[Int]$HandleStop,

		#Take a tolerance level for the RAM handles.  If the RAM handles does not change by more than the tolerance, consider it unchanged
		[Alias("Tol")]
		[Int]$Tolerance = 3,

		#Take a switch to force the function into one of the "Write" sets
		[Parameter(ParameterSetName="WriteName")]
		[Parameter(ParameterSetName="WriteProc")]
		[Parameter(ParameterSetName="WriteNameRestart")]
		[Parameter(ParameterSetName="WriteProcRestart")]
		[Alias("Write")]
		[Switch]$WriteOut,

		#Take a string to display as the process name as the third parameter in the "Write" sets
		[Parameter(Position=2, Mandatory=$True, ParameterSetName="WriteName")]
		[Parameter(Position=2, Mandatory=$True, ParameterSetName="WriteProc")]
		[Parameter(Position=2, Mandatory=$True, ParameterSetName="WriteNameRestart")]
		[Parameter(Position=2, Mandatory=$True, ParameterSetName="WriteProcRestart")]
		[Alias("Display","WN")]
		[String]$WriteName,

		#Take a timespan representing the time after which to assume the process is stuck as the fourth paramter
		[Parameter(Position=3)]
		[Alias("Timeout")]
		[Timespan]$StuckTime = [Timespan]::FromSeconds(30),

		#Take a timespan represnting the time to wait between RAM handle checks as the 5th parameter
		[Parameter(Position=4)]
		[Alias("CheckInt","Check")]
		[Timespan]$CheckInterval = [Timespan]::FromMilliseconds(100),

		#Take a switch in the "Name" sets to cause the function to wait for the process to start if it's not running
		[Parameter(ParameterSetName="Name")]
		[Parameter(ParameterSetName="WriteName")]
		[Parameter(ParameterSetName="NameRestart")]
		[Parameter(ParameterSetName="WriteNameRestart")]
		[Alias("Wait")]
		[Switch]$WaitStart,

		#Take a timespan as the 6th parameter in the "Name" sets representing the time to wait between checks to see if the process is running
		[Parameter(Position=5, ParameterSetName="Name")]
		[Parameter(Position=5, ParameterSetName="WriteName")]
		[Parameter(Position=5, ParameterSetName="NameRestart")]
		[Parameter(Position=5, ParameterSetName="WriteNameRestart")]
		[Alias("WaitTime","WI")]
		[Timespan]$WaitInterval = [Timespan]::FromSeconds(1),

		#Take a timespan as the 7th parameter in the "Name" sets representing the time after which to abort waiting for the process to start
		[Parameter(Position=6, ParameterSetName="Name")]
		[Parameter(Position=6, ParameterSetName="WriteName")]
		[Parameter(Position=6, ParameterSetName="NameRestart")]
		[Parameter(Position=6, ParameterSetName="WriteNameRestart")]
		[Alias("WT")]
		[Timespan]$WaitTimeout = [Timespan]::FromMinutes(5),

		#Take a flag to cause the function to restart a stalled process in the "Restart"
		[Parameter(ParameterSetName="NameRestart")]
		[Parameter(ParameterSetName="WriteNameRestart")]
		[Parameter(ParameterSetName="ProcRestart")]
		[Parameter(ParameterSetName="WriteProcRestart")]
		[Switch]$Restart,

		#Take a mandatory script block to execute in order to start the process after killing it as the 8th parameter in the "Restart" sets
		[Parameter(Position=7, Mandatory=$True, ParameterSetName="NameRestart")]
		[Parameter(Position=7, Mandatory=$True, ParameterSetName="WriteNameRestart")]
		[Parameter(Position=7, Mandatory=$True, ParameterSetName="ProcRestart")]
		[Parameter(Position=7, Mandatory=$True, ParameterSetName="WriteProcRestart")]
		[Alias("Script","RS")]
		[Management.Automation.ScriptBlock]$RestartScript,

		#Take a handle count under which the process should not be restarted
		[Parameter(Position=8, Mandatory=$True, ParameterSetName="NameRestart")]
		[Parameter(Position=8, Mandatory=$True, ParameterSetName="WriteNameRestart")]
		[Parameter(Position=8, Mandatory=$True, ParameterSetName="ProcRestart")]
		[Parameter(Position=8, Mandatory=$True, ParameterSetName="WriteProcRestart")]
		[Alias("StartAt","LowStop","Start")]
		[Int]$StartCount,

		#Take a switch to start high and wait for a low, rather than starting low and waiting for a high
		[Switch]$Low,

		#Take a switch to avoid waiting the first interval in the event that the target has already hit the desired RAM handle count
		[Switch]$NoWait
	)

	#If we're in one of the "Name" parameter sets
	If ($PSCmdlet.ParameterSetName -like "*Name*") {
		#Use Get-Process to find the running executable
		$Process = Get-Process -ErrorAction SilentlyContinue -Name $ProcessName
		#If there's no process and we're waiting for the process to start
		If (!$Process -and $WaitStart) {
			#If writing output, alert the user
			If ($WriteOut) {
				Write-Output "$WriteName process is not running.  Waiting for process to start..."
			}
			#Start a timer
			$Timer = [Diagnostics.Stopwatch]::StartNew()
			#While there's no process to watch
			While (!$Process) {
				#If the timeout has elapsed
				If ($Timer.Elapsed -ge $WaitTimeout) {
					#Alert the user and break the loop
					Write-Output "Timeout has expired!"
					Break
				}
				#Sleep for the wait interval
				Start-Sleep -Milliseconds $WaitInterval.TotalMilliseconds
				#Search for the process again
				$Process = Get-Process -ErrorAction SilentlyContinue -Name $ProcessName
			}
			#Stop the timer
			$Timer.Stop()
		}
		#If there's no process, throw an error
		If (!$Process) {
			Throw "Process not found!"
		}
		#If writing output, alert the user that the process is running
		If ($WriteOut) {
			Write-Output "$writename process is running."
		}
	#Otherwise, if we're in one of the "Proc" sets
	} Else {
		#If the user did not specify a process or if it exited, throw an error
		If (!$Process -or $Process.HasExited) {
			Throw "Invalid process specified!"
		}
	}

	#If writing output, alert the user that we're waiting for the process
	If ($WriteOut) {
		Write-Output "Waiting for $WriteName process.  RAM Handles count:"
	}

	#If the loop is already going to terminate, and we've got a NoWait flag
	#This is a simplified version of (Not (loop continue condition) and $NoWait)
	If ($NoWait -and (($Process.HandleCount -ge $HandleStop) -or $Low) -and !(($Process.HandleCount -gt $HandleStop) -and $Low)) {
		#Set the check interval to 0 (don't pause during the loop)
		$CheckInterval = New-Timespan
	}

	#Start a timer
	$Timer = [Diagnostics.Stopwatch]::StartNew()
	#Start a loop
	Do {
		#If writing output, display the current RAM handle count and the change in the last 30 seconds
		If ($WriteOut) {
			Write-Update "$($Process.HandleCount) / $HandleStop ($([Math]::Abs($LastHandleCount - $Process.HandleCount)) change in the last $([Int]$Timer.Elapsed.TotalSeconds) seconds)"
		}
		#If the handle count is within the tolerance since the last update
		If ([Math]::Abs($LastHandleCount - $Process.HandleCount) -lt $Tolerance) {
			#Set a flag indicating whether or not to restart based on the RAM handle count (if it's on the wrong side of StartCount, don't restart)
			[Bool]$RestartTest = ((($Process.HandleCount -lt $StartCount) -and $Low) -or (($Process.HandleCount -gt $StartCount) -and !$Low))
			#If the stuck time has been exceeded, the reset flag is set, and the handle count is on the right side of StartCount
			If (($Timer.Elapsed -ge $StuckTime) -and $Restart -and $RestartTest) {
				#If writing output, alert the user that the process is stuck and it's being terminated
				If ($WriteOut) {
					Write-Update "$WriteName process appears to be stuck at $($Process.HandleCount) RAM handles!"
					Write-Output ""
					Write-Output "Terminating $WriteName process..."
				}
				#Kill the process
				$Process.Kill()
				#Execute the restart script provided
				$Process = .$RestartScript
				#If the restart script did not return a process, throw an error
				If (!$Process) {
					Throw "Unable to keep track of $WriteName process!  Restart script must return a process object!"
				}
				#If writing output, alert the user that we're waiting for the process
				If ($WriteOut) {
					Write-Output "Waiting for $WriteName process.  RAM handles count:"
				}
			}
		#If the RAM handle count is different than last check
		} Else {
			#Reset the timer
			$Timer.Restart()
		}
		#Store the last handle count, if the change has exceeded the tolerance
		If ([Math]::Abs($LastHandleCount - $Process.HandleCount) -ge $Tolerance) {
			$LastHandleCount = $Process.HandleCount
		}
		#Sleep for the check interval
		Start-Sleep -Milliseconds $CheckInterval.TotalMilliseconds
		#Refresh the process information
		$Process.Refresh()
		#If the process has stopped
		If ($Process.HasExited) {
			#If writing output, alert the user
			If ($WriteOut) {
				Write-Output ""
				Write-Output "$WriteName process has exited."
			}
			#Return false
			Return $False
		}
	#Loop While the handle count is lower than desired (or higher than desired, if the Low flag was provided)
	} While ((($Process.HandleCount -lt $HandleStop) -and !$Low) -or (($Process.HandleCount -gt $HandleStop) -and $Low))

	#If writing output, alert the user that the desired RAM handle count has been reached
	If ($WriteOut) {
		Write-Output ""
		Write-Output "$WriteName process has reached $HandleStop RAM handles."
	}

	#Return true
	Return $True
}

Function Wait-ProcessIdle {
	#This defaults the parameter set to "Name".  They can force it into "Proc", "WriteName" or "WriteProc" by providing parameters included in one of these sets
	[CmdletBinding(DefaultParameterSetName="Name")]
	#Parameter Declaration
	Param(
		#Take a string that's the name of the process to look for as the first parameter in the "Name" and "WriteName" sets
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="Name")]
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="WriteName")]
		[Alias("Name","PN")]
		[String]$ProcessName,
		
		#Take a process to wait for as the first parameter in the "Proc" and "WriteProc" sets
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="Proc")]
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="WriteProc")]
		[Alias("Proc")]
		[Diagnostics.Process]$Process,
		
		#Take a timespan indicating how long the program must be idle for as the second parameter
		[Parameter(Position=1)]
		[Alias("Stable","Idle","IdleTime")]
		[Timespan]$StableTime = [Timespan]::FromMilliseconds(500),
		
		#Take a timespan indicating how frequently to check CPU time as the third parameter
		[Parameter(Position=2)]
		[Alias("CheckInt","Check")]
		[Timespan]$CheckInterval = [Timespan]::FromMilliseconds(100),
		
		#Take a switch in the "Name" sets to cause the function to wait for the process to start if it's not running
		[Parameter(ParameterSetName="Name")]
		[Parameter(ParameterSetName="WriteName")]
		[Alias("Wait")]
		[Switch]$WaitStart,
		
		#Take a timespan as the 4th parameter in the "Name" sets representing the time to wait between checks to see if the process is running
		[Parameter(Position=3, ParameterSetName="Name")]
		[Parameter(Position=3, ParameterSetName="WriteName")]
		[Alias("WaitTime","WI")]
		[Timespan]$WaitInterval = [Timespan]::FromSeconds(1),
		
		#Take a timespan as the 5th parameter in the "Name" sets representing the time after which to abort waiting for the process to start
		[Parameter(Position=4, ParameterSetName="Name")]
		[Parameter(Position=4, ParameterSetName="WriteName")]
		[Alias("WT")]
		[Timespan]$WaitTimeout = [Timespan]::FromSeconds(120),
		
		#Take a switch to force the function into one of the "Write" sets
		[Parameter(ParameterSetName="WriteName")]
		[Parameter(ParameterSetName="WriteProc")]
		[Alias("Write")]
		[Switch]$WriteOut,
		
		#Take a string to display as the process name as the 6th parameter in the "Write" sets
		[Parameter(Mandatory=$True, Position=5, ParameterSetName="WriteName")]
		[Parameter(Mandatory=$True, Position=5, ParameterSetName="WriteProc")]
		[Alias("Display","WN")]
		[String]$WriteName
	)
	
	#If we're in one of the "Name" parameter sets
	If ($PSCmdlet.ParameterSetName -like "*Name") {
		#Use Get-Process to find the running executable
		$Process = Get-Process -ErrorAction SilentlyContinue -Name $ProcessName
		#If there's no process and we're waiting for the process to start
		If (!$Process -and $WaitStart) {
			#If writing output, alert the user
			If ($WriteOut) {
				Write-Output "$WriteName process is not running.  Waiting for process to start..."
			}
			#Start a timer
			$Timer = [Diagnostics.Stopwatch]::StartNew()
			#While there's no process to watch
			While (!$Process) {
				#If the timeout has elapsed
				If ($Timer.Elapsed -ge $WaitTimeout) {
					#Alert the user and break the loop
					Write-Output "Timeout has expired!"
					Break
				}
				#Sleep for the wait interval
				Start-Sleep -Milliseconds $WaitInterval.TotalMilliseconds
				#Search for the process again
				$Process = Get-Process -ErrorAction SilentlyContinue -Name $ProcessName
			}
			#Stop the timer
			$Timer.Stop()
		}
		#If there's no process, throw an error
		If (!$Process) {
			Throw "Process not found!"
		}
		#If writing output, alert the user that the process is running
		If ($WriteOut) {
			Write-Output "$writename process is running."
		}
	#Otherwise, if we're in one of the "Proc" sets
	} Else {
		#If the user did not specify a process or if it exited, throw an error
		If (!$Process -or $Process.HasExited) {
			Throw "Invalid process specified!"
		}
	}
	
	#If writing output, alert the user that we're waiting for the process
	If ($WriteOut) {
		Write-Output "Waiting for $WriteName process to idle..."
	}
	
	#Wait for the process to start getting time on the CPU
	While ($Process.CPU -eq 0) {
		#Sleep for the check interval
		Start-Sleep -Milliseconds $CheckInterval.TotalMilliseconds
		#Refresh the process information
		$Process.Refresh()
		#If the process has exited
		If ($Process.HasExited) {
			#If writing output, alert the user
			If ($WriteOut) {
				Write-Output "$WriteName process has exited."
			}
			#Return false
			Return $False
		}
	}
	
	#Start the last CPU time at -1, because it's impossible to match that initially - this ensures that the process will be idle for the full idle time
	$LastCPU = -1
	#Start a timer
	$Timer = [Diagnostics.Stopwatch]::StartNew()
	#Loop while the idle time has not elapsed
	While ($Timer.Elapsed -le $StableTime) {
		#If the current CPU time doesn't match the last CPU time
		If ($Process.CPU -ne $LastCPU) {
			#Restart the idle timer
			$Timer.Restart()
			#Update the last CPU time
			$LastCPU = $Process.CPU
		}
		#Sleep for the check interval
		Start-Sleep -Milliseconds $CheckInterval.TotalMilliseconds
		#Refresh the process information
		$Process.Refresh()
		#If the process has stopped
		If ($Process.HasExited) {
			#If writing output, alert the user
			If ($WriteOut) {
				Write-Output "$WriteName process has exited."
			}
			#Return false
			Return $False
		}
	}
	
	#If writing output, alert the user that the process has idled for the requisite time
	If ($WriteOut) {
		Write-Output "$WriteName process has idled."
	}
	#Return true
	Return $True
}

Function Wait-ProcessMainWindow {
	#This defaults the parameter set to "Name".  They can force it into "Proc", "WriteName" or "WriteProc" by providing parameters included in one of these sets
	[CmdletBinding(DefaultParameterSetName="Name")]
	#Parameter Declaration
	Param(
		#Take a string that's the name of the process to look for as the first parameter in the "Name" and "WriteName" sets
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="Name")]
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="WriteName")]
		[Alias("Name","PN")]
		[String]$ProcessName,
		
		#Take a process to wait for as the first parameter in the "Proc" and "WriteProc" sets
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="Proc")]
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="WriteProc")]
		[Alias("Proc")]
		[Diagnostics.Process]$Process,
		
		#Take a pointer indicating the original window handle
		[Parameter(Position=1)]
		[Alias("Handle","OH")]
		[IntPtr]$OriginalHandle = 0,
		
		#Take a timespan indicating how frequently to check CPU time as the third parameter
		[Parameter(Position=2)]
		[Alias("CheckInt","Check")]
		[Timespan]$CheckInterval = [Timespan]::FromMilliseconds(100),
		
		#Take a switch in the "Name" sets to cause the function to wait for the process to start if it's not running
		[Parameter(ParameterSetName="Name")]
		[Parameter(ParameterSetName="WriteName")]
		[Alias("Wait")]
		[Switch]$WaitStart,
		
		#Take a timespan as the 4th parameter in the "Name" sets representing the time to wait between checks to see if the process is running
		[Parameter(Position=3, ParameterSetName="Name")]
		[Parameter(Position=3, ParameterSetName="WriteName")]
		[Alias("WaitTime","WI")]
		[Timespan]$WaitInterval = [Timespan]::FromSeconds(1),
		
		#Take a timespan as the 5th parameter in the "Name" sets representing the time after which to abort waiting for the process to start
		[Parameter(Position=4, ParameterSetName="Name")]
		[Parameter(Position=4, ParameterSetName="WriteName")]
		[Alias("WT")]
		[Timespan]$WaitTimeout = [Timespan]::FromSeconds(120),
		
		#Take a switch to force the function into one of the "Write" sets
		[Parameter(ParameterSetName="WriteName")]
		[Parameter(ParameterSetName="WriteProc")]
		[Alias("Write")]
		[Switch]$WriteOut,
		
		#Take a string to display as the process name as the 6th parameter in the "Write" sets
		[Parameter(Mandatory=$True, Position=5, ParameterSetName="WriteName")]
		[Parameter(Mandatory=$True, Position=5, ParameterSetName="WriteProc")]
		[Alias("Display","WN")]
		[String]$WriteName
	)
	
	#If we're in one of the "Name" parameter sets
	If ($PSCmdlet.ParameterSetName -like "*Name") {
		#Use Get-Process to find the running executable
		$Process = Get-Process -ErrorAction SilentlyContinue -Name $ProcessName
		#If there's no process and we're waiting for the process to start
		If (!$Process -and $WaitStart) {
			#If writing output, alert the user
			If ($WriteOut) {
				Write-Output "$WriteName process is not running.  Waiting for process to start..."
			}
			#Start a timer
			$Timer = [Diagnostics.Stopwatch]::StartNew()
			#While there's no process to watch
			While (!$Process) {
				#If the timeout has elapsed
				If ($Timer.Elapsed -ge $WaitTimeout) {
					#Alert the user and break the loop
					Write-Output "Timeout has expired!"
					Break
				}
				#Sleep for the wait interval
				Start-Sleep -Milliseconds $WaitInterval.TotalMilliseconds
				#Search for the process again
				$Process = Get-Process -ErrorAction SilentlyContinue -Name $ProcessName
			}
			#Stop the timer
			$Timer.Stop()
		}
		#If there's no process, throw an error
		If (!$Process) {
			Throw "Process not found!"
		}
		#If writing output, alert the user that the process is running
		If ($WriteOut) {
			Write-Output "$writename process is running."
		}
	#Otherwise, if we're in one of the "Proc" sets
	} Else {
		#If the user did not specify a process or if it exited, throw an error
		If (!$Process -or $Process.HasExited) {
			Throw "Invalid process specified!"
		}
	}
	
	#If writing output, alert the user that we're waiting for the main window handle
	If ($WriteOut) {
		Write-Output "Waiting for $WriteName process main window handle to change..."
	}
	
	#Loop while the main window handle has not changed
	While ($Process.MainWindowHandle -eq $OriginalHandle) {
		#Sleep for the check interval
		Start-Sleep -Milliseconds $CheckInterval.TotalMilliseconds
		#Refresh the process information
		$Process.Refresh()
		#If the process has stopped
		If ($Process.HasExited) {
			#If writing output, alert the user
			If ($WriteOut) {
				Write-Output "$WriteName process has exited."
			}
			#Return false
			Return $False
		}
	}
	
	#If writing output, alert the user to the updated main window handle
	If ($WriteOut) {
		Write-Output "$WriteName process main window handle is now $($Process.MainWindowHandle)."
	}
	#Return true
	Return $True
}

Function Wait-ProcessClose {
	#This defaults the parameter set to "Name".  They can force it into "Proc", "WriteName" or "WriteProc" by providing parameters included in one of these sets
	[CmdletBinding(DefaultParameterSetName="Name")]
	#Parameter Declaration
	Param(
		#Take a string that's the name of the process to look for as the first parameter in the "Name" and "WriteName" sets
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="Name")]
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="WriteName")]
		[Alias("Name","PN")]
		[String]$ProcessName,
		
		#Take a process to wait for as the first parameter in the "Proc" and "WriteProc" sets
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="Proc")]
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="WriteProc")]
		[Alias("Proc")]
		[Diagnostics.Process]$Process,
		
		#Take a timespan indicating how frequently to check the process
		[Parameter(Position=1)]
		[Alias("CheckInt","Check")]
		[Timespan]$CheckInterval = [Timespan]::FromMilliseconds(100),
		
		#Take a timespan indicating the maximum time to wait
		[Parameter(Position=2)]
		[Alias("Time")]
		[Timespan]$Timeout = [Timespan]::FromMinutes(2),
		
		#Take a switch to force the function into one of the "Write" sets
		[Parameter(ParameterSetName="WriteName")]
		[Parameter(ParameterSetName="WriteProc")]
		[Alias("Write")]
		[Switch]$WriteOut,
		
		#Take a string to display as the process name as the 6th parameter in the "Write" sets
		[Parameter(Mandatory=$True, Position=3, ParameterSetName="WriteName")]
		[Parameter(Mandatory=$True, Position=3, ParameterSetName="WriteProc")]
		[Alias("Display","WN")]
		[String]$WriteName
	)
	
	#If we're in one of the "Name" parameter sets
	If ($PSCmdlet.ParameterSetName -like "*Name") {
		#Use Get-Process to find the running executable
		$Process = Get-Process -ErrorAction SilentlyContinue -Name $ProcessName
	#Otherwise, if we're in one of the "Proc" sets
	}
	
	#If the user did not specify a process or if it exited, return true
	If (!$Process -or $Process.HasExited) {
		If ($WriteOut) {
			Write-Output "$WriteName process has exited."
			Return $True
		}
	}
	
	#If writing output, alert the user that we're waiting for the process
	If ($WriteOut) {
		Write-Output "Waiting for $WriteName process to exit..."
	}
	
	#Start a timer
	$Timer = [Diagnostics.Stopwatch]::StartNew()
	#Loop while the idle time has not elapsed
	While (!($Process.HasExited)) {
		#Sleep for the check interval
		Start-Sleep -Milliseconds $CheckInterval.TotalMilliseconds
		#Refresh the process information
		$Process.Refresh()
		#If the process has stopped
		If ($Timer.Elapsed -ge $Timeout) {
			#If writing output, alert the user
			If ($WriteOut) {
				Write-Output "Timeout exceeded."
				Write-Output "$WriteName process has not exited."
			}
			#Return false
			Return $False
		}
	}
	
	#If writing output, alert the user that the process has idled for the requisite time
	If ($WriteOut) {
		Write-Output "$WriteName process has exited."
	}
	#Return true
	Return $True
}

Function Restart-Process {
	[CmdletBinding(DefaultParameterSetName="Name")]
	Param(
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="Name")]
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="WriteName")]
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="FlagsName")]
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="FlagsWriteName")]
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="ExtName")]
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="ExtWriteName")]
		[Alias("Name", "PN")]
		[String]$ProcessName,
		
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="Proc")]
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="WriteProc")]
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="FlagsProc")]
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="FlagsWriteProc")]
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="ExtName")]
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="ExtWriteName")]
		[Alias("Proc")]
		[Diagnostics.Process]$Process,
		
		[Parameter(Position=1)]
		[Alias("Args")]
		[String]$StartArgs="",
		
		[Parameter(ParameterSetName="WriteName")]
		[Parameter(ParameterSetName="WriteProc")]
		[Parameter(ParameterSetName="FlagsWriteName")]
		[Parameter(ParameterSetName="FlagsWriteProc")]
		[Parameter(ParameterSetName="ExtWriteName")]
		[Parameter(ParameterSetName="ExtWriteProc")]
		[Alias("Write")]
		[Switch]$WriteOut,
		
		[Parameter(Mandatory=$True, Position=2, ParameterSetName="WriteName")]
		[Parameter(Mandatory=$True, Position=2, ParameterSetName="WriteProc")]
		[Parameter(Mandatory=$True, Position=2, ParameterSetName="FlagsWriteName")]
		[Parameter(Mandatory=$True, Position=2, ParameterSetName="FlagsWriteProc")]
		[Parameter(Mandatory=$True, Position=2, ParameterSetName="ExtWriteName")]
		[Parameter(Mandatory=$True, Position=2, ParameterSetName="ExtWriteProc")]
		[Alias("Display", "WN")]
		[String]$WriteName,
		
		
		[Parameter(ParameterSetName="FlagsName")]
		[Parameter(ParameterSetName="FlagsWriteName")]
		[Parameter(ParameterSetName="FlagsProc")]
		[Parameter(ParameterSetName="FlagsWriteProc")]
		[Switch]$UseFlags,
		
		[Parameter(Mandatory=$True, Position=3, ParameterSetName="FlagsName")]
		[Parameter(Mandatory=$True, Position=3, ParameterSetName="FlagsWriteName")]
		[Parameter(Mandatory=$True, Position=3, ParameterSetName="FlagsProc")]
		[Parameter(Mandatory=$True, Position=3, ParameterSetName="FlagsWriteProc")]
		[String]$Flags,
		
		[Parameter(ParameterSetName="ExtName")]
		[Parameter(ParameterSetName="ExtWriteName")]
		[Parameter(ParameterSetName="ExtProc")]
		[Parameter(ParameterSetName="ExtWriteProc")]
		[Switch]$UseExternal,
		
		[Parameter(Mandatory=$True, Position=3, ParameterSetName="ExtName")]
		[Parameter(Mandatory=$True, Position=3, ParameterSetName="ExtWriteName")]
		[Parameter(Mandatory=$True, Position=3, ParameterSetName="ExtProc")]
		[Parameter(Mandatory=$True, Position=3, ParameterSetName="ExtWriteProc")]
		[String]$External,
		
		[Alias("Force", "Kill")]
		[Switch]$ForceClose,
		
		[Parameter(Position=4)]
		[Alias("CheckInt","Check")]
		[Timespan]$CheckInterval = [Timespan]::FromMilliseconds(100),
		
		[Parameter(Position=5)]
		[Alias("Time")]
		[Timespan]$Timeout = [Timespan]::FromSeconds(30)
	)
	
	If ($PSCmdlet.ParameterSetName -like "*Name") {
		If ($WriteOut) {
			Write-Output "Acquiring handle for $WriteName process..."
		}
		$Process = Get-Process -ErrorAction SilentlyContinue -Name $ProcessName
	}
	
	If (!$Process -or $Process.HasExited) {
		Throw "Invalid process specified!"
	}
	
	$Path = $Process.Path
	
	If ($UseExternal) {
		If ($WriteOut) {
			Write-Output "Stopping $WriteName process using external command: ""$External""..."
		}
		cmd /c "$External"
	} ElseIf ($UseFlags) {
		If ($WriteOut) {
			Write-Output "Stopping $WriteName process using flags: ""$Flags""..."
		}
		Start-Process $Path -ArgumentList $Flags
	} Else {
		If ($WriteOut) {
			Write-Output "Stopping $WriteName process by closing main window..."
		}
		$Process.CloseMainWindow()
	}
	
	If ($ForceClose -and !$(Wait-ProcessClose $Process -WriteOut:$WriteOut -WriteName $WriteName -CheckInterval $CheckInterval -Timeout $Timeout)) {
		If ($WriteOut) {
			Write-Output "$WriteName process is not stopping.  Force closing..."
		}
		$Process.Kill()
		$ForceClose = $False
	}
	If (!$ForceClose -and !$(Wait-ProcessClose $Process -WriteOut:$WriteOut -WriteName $WriteName -CheckInterval $CheckInterval -Timeout $Timeout)) {
		If ($WriteOut) {
			Write-Output "Unable to stop $WriteName process!"
		}
		Return $False
	}
	
	If ($WriteOut -and $StartArgs) {
		Write-Output "Starting $WriteName process with arguments ""$StartArgs""..."
	} ElseIf ($WriteOut) {
		Write-Output "Starting $WriteName process..."
	}
	
	If ($StartArgs) {
		Start-Process $Path -ArgumentList $StartArgs
	} Else {
		Start-Process $Path
	}
	
	If ($WriteOut) {
		Write-Output "$WriteName process started."
	}
	Return $True
}

Function Format-String {
	Param (
		[Parameter(Position=0, ValueFromRemainingArguments=$True)]
		[String[]]$String,
		
		[ValidateScript({If ($Truncate) {$_ -ge 4} Else {$_ -ge 1}})]
		[Int]$Width = $($Host.UI.RawUI.WindowSize.Width),
		
		[Int]$Indent = 0,
		
		[String]$WordChars = "^\s-",
		
		[Switch]$Trim,
		
		[Switch]$TrimStart,
		
		[Switch]$TrimEnd,
		
		[Switch]$WordWrap,
		
		[Switch]$Truncate,
		
		[Switch]$Wrap,
		
		[Switch]$Stream
	)
	
	If (([bool]$Wrap + [bool]$WordWrap + [bool]$Truncate) -gt 1) {
		Throw "Cannot mix truncation and wrapping methods!"
	}
	
	If ($WordWrap -and $Width -eq 1) {
		$WordWrap = $False
		$Wrap = $True
		$String = $String.ForEach({$_.Replace(" ", "")})
	}
	
	$Outp = New-Object System.Collections.ArrayList
	$Width -= $Indent
	If ($WordChars[0] -eq "[" -and $WordChars[-1] -eq "]") {
		$WordChars = $WordChars.SubString(1, $WordChars.Length-2)
	}
	
	ForEach ($Line in $String) {
		$Line = $Line.TrimEnd()
		If ($WordWrap) {
			$Last = 0
			For ($Cursor = $Width; $Cursor -lt $Line.Length; $Cursor += $Width) {
				While ($Cursor -ge $Last -and $Line[$Cursor] -match "[$WordChars]") {
					$Cursor--
				}
				If ($Cursor -le $Last) {
					$Cursor += $Width
				}
				$Null = $Outp.Add("$(" "*$Indent)$($Line.SubString($Last, $Cursor-$Last).TrimEnd())")
				While (!($Line.SubString($Cursor, 1).Trim())) {
					$Cursor++
				}
				$Last = $Cursor
			}
			$Line = $Line.SubString($Last)
		} ElseIf ($Truncate -and $Line.Length -gt $Width) {
			$Line = "$($Line.Remove($Width-3))..."
		} ElseIf ($Wrap) {
			While ($Line.Length -gt $Width) {
				$Null = $Outp.Add("$(" "*$Indent)$($Line.Remove($Width))")
				$Line = $Line.SubString($Width)
			}
		}
		$Null = $Outp.Add("$(" "*$Indent)$Line")
	}
	
	While (($Trim -or $TrimStart) -and $Outp[0].Trim() -eq "") {
		$Outp.RemoveAt(0)
	}
	While (($Trim -or $TrimEnd) -and $Outp.Item($Outp.Count-1).Trim() -eq "") {
		$Outp.RemoveAt($Outp.Count-1)
	}
	
	If ($Stream) {
		Return $Outp
	} Else {
		Return $($Outp -join "`r`n")
	}
}

Function Get-MemberRecurse {
	Param(
		[Parameter(Position=0)]
		[PSObject]$Obj,
		
		[ValidateRange(1, [Int]::MaxValue)]
		[Int]$Width = $($Host.UI.RawUI.WindowSize.Width),
		
		[Switch]$NoTruncate,
		
		[Switch]$Group
	)

	Function Format-GM {
		Param(
			[Object[]]$Table,
			[Switch]$Stream
		)
		
		$MaxNameLen = 4
		$MaxTypeLen = 10
		
		ForEach ($Entry in $Table) {
			If ("$($Entry.Name)".Length -gt $MaxNameLen) {
				$MaxNameLen = "$($Entry.Name)".Length
			}
			If ("$($Entry.MemberType)".Length -gt $MaxTypeLen) {
				$MaxTypeLen = "$($Entry.MemberType)".Length
			}
		}
		
		$MaxNameLen++
		$MaxTypeLen++
		
		$Outp = New-Object System.Collections.ArrayList
		$Null = $Outp.Add("   TypeName: $($Table[0].TypeName)")
		$Null = $Outp.Add("Name$(" "*($MaxNameLen-4))MemberType$(" "*($MaxTypeLen-10))Definition")
		$Null = $Outp.Add("----$(" "*($MaxNameLen-4))----------$(" "*($MaxTypeLen-10))----------")
		
		ForEach ($Entry in $Table) {
			$EntryName = "$($Entry.Name)"
			$EntryType = "$($Entry.MemberType)"
			$Null = $Outp.Add("$($EntryName)$(" "*($MaxNameLen-$EntryName.Length))$($EntryType)$(" "*($MaxTypeLen-$EntryType.Length))$($Entry.Definition)")
		}
		
		If ($Stream) {
			Return $Outp
		} Else {
			Return $($Outp -join "`r`n")
		}
	}

	Function Get-ChildMemberRecurse {
		Param(
			[PSObject]$Obj,
			[String]$Name,
			[Hashtable]$Seen,
			[System.Collections.ArrayList]$Output,
			[Hashtable]$Groups,
			[Int]$Indent = 0
		)
		$Type = $Obj.GetType()
		If (!$Groups.Contains($Type)) {
			$Groups[$Type] = New-Object System.Collections.ArrayList
		}
		$Null = $Groups[$Type].Add($Name)
		If (!$Seen[$Type]) {
			$Seen[$Type] = $True
			$Null = $Output.Add(@($Indent, "${name}:", $(Format-GM $(Get-Member -InputObject $Obj) -Stream), $Type))
			ForEach ($Child in $(Get-Member -InputObject $Obj -MemberType Property)) {
				Try {
					$ChildObj = Select-Object -InputObject $Obj -ExpandProperty $Child.Name -ErrorAction Stop
					Get-ChildMemberRecurse $ChildObj "$Name.$($Child.Name)" $Seen $Output $Groups ($Indent+2)
				} Catch {
					Try {
						$ChildName = $Child.GetType()
					} Catch {
						$ChildName = "Unknown Type"
					}
					$Null = $Output.Add(@(($Indent+2), "$Name.$($Child.Name)", "Unable to get members!", $Type))
				}
			}
			$Seen.Remove($Type)
		}
	}
	
	$Name = $Obj.GetType().Name
	$Seen = @{}
	$Output = New-Object System.Collections.ArrayList
	$Groups = @{}

	Get-ChildMemberRecurse $Obj $Name $Seen $Output $Groups

	If ($Group) {
		ForEach ($Entry in $Output) {
			$Type = $Entry[3]
			If ($Type.Name) {
				$TypeName = $Type.Name
			} Else {
				$TypeName = $Type
			}
			If (!$Seen.Contains($Type)) {
				$Seen[$Type] = $True
				$DispArray = $Entry[2]
				if ($NoTruncate) {
					$GroupStr = Format-String -Trim -Indent 4 $($Groups[$Type] -join ", ")
					$DispStr = Format-String -Trim -Indent 4 @DispArray
				} Else {
					$GroupStr = Format-String -Trim -Indent 4 -WordWrap -Width $Width $($Groups[$Type] -join ", ")
					$DispStr = Format-String -Trim -Indent 4 -Truncate -Width $Width @DispArray
				}
				Write-Output "`r`n"
				Write-Output "Type $TypeName contains the following objects:"
				Write-Output $GroupStr
				Write-Output "Members of ${TypeName}:"
				Write-Output $DispStr
			}
			
		}
	} Else {
		ForEach ($Entry in $Output) {
			$Indent = $Entry[0]
			Write-Output "`r`n"
			Write-Output $(Format-String $Entry[1] -Indent $Indent)
			$Disparray = $Entry[2]
			$Indent += 2
			if ($NoTruncate) {
				Write-Output $(Format-String -Trim -Indent $Indent @DispArray)
			} Else {
				Write-Output $(Format-String -Trim -Indent $Indent -Truncate -Width $Width @DispArray)
			}
		}
	}
}
