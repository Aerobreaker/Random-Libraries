<# TODO:

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

Function Write-Indirectable {
	Param(
		[Parameter(Position=0, ValueFromPipeline=$True)]
		[PSObject] $InputObject,
		
		[String] $Separator = " ",
		
		[System.ConsoleColor] $ForegroundColor = ([Console]::ForegroundColor),
		
		[System.ConsoleColor] $BackgroundColor = ([Console]::BackgroundColor),
		
		[Switch] $NoNewLine
	)
	$CurrentFG = [Console]::ForegroundColor
	$CurrentBG = [Console]::BackgroundColor
	[Console]::ForegroundColor = $ForegroundColor
	[Console]::BackgroundColor = $BackgroundColor
	If ($InputObject.GetEnumerator -and $InputObject -IsNot [String]) {
		$OutputString = Out-String -InputObject ($InputObject.GetEnumerator() -join $Separator) -NoNewLine
	} Else {
		$OutputString = Out-String -InputObject $InputObject -NoNewLine
	}
	If ($NoNewLine) {
		[Console]::Write($OutputString)
	} Else {
		[Console]::WriteLine($OutputString)
	}
	[Console]::ForegroundColor = $CurrentFG
	[Console]::BackgroundColor = $CurrentBG
}

Function Validate-HostName {
	<#
		Verify that a string is a valid hostname
	#>
	Param (
		# Take one argument - the string to check
		[String]$HostName
	)

	# If the host name ends with a ., remove it
	If ($HostName -match "\.$") {
		$HostName = $HostName.Remove($HostName.Length - 1)
	}

	# If the hostname is 0 characters or >255 characters, fail
	If (($HostName.Length -lt 1) -or ($HostName.Length -gt 255)) {
		Return $False
	}

	$Out = $True
	# Iterate through each label
	$HostName.Split(".").ForEach({
		# If the label is >63 characters, or doesn't start and end with an alphanumeric, or includes characters which are not alphanumeric or hyphen, fail
		If (($_.Length -gt 63) -or !($_ -match "^([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])$")) {
			$Out = $False
			# Break the for loop early (break ends the whole function)
			Return
		}
	})

	Return $Out
}

Function Validate-IPAddress {
	<#
		Verify that a string is a valid IP address
	#>
	Param (
		# Take one argument - the IP to check
		[String]$IPAddress
	)

	# If the string isn't comprised of exactly 4 octets, fail
	If (!($IPAddress -match "^(\d{1,3}\.){3}\d{1,3}$")) {
		Return $False
	}

	$Out = $True
	# Iterate through each octet
	$IPAddress.Split(".").ForEach({
		# If the octet is greater than 255, fail
		If ([Int]$_ -gt 255) {
			$Out = $False
			# Break the loop early (break ends the whole function)
			Return
		}
	})

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
	
	# This defaults the parameter set to "Host".  It can be forced into "Array" by providing an array
	[CmdletBinding(DefaultParameterSetName='Host')]
	Param (
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="Array")]
		[ValidateCount(1,3)]
		[Array]$ParamArray,

		[Parameter(Mandatory=$True, Position=0, ParameterSetName="Host")]
		[Alias("Resource","Name","Dest")]
		[ValidateScript({Validate-HostName $_})]
		[String]$ResourceName,

		[Parameter(Mandatory=$True, Position=0, ParameterSetName="IP")]
		[Alias("DestIP","IP")]
		[ValidateScript({Validate-IPAddress $_})]
		[String]$IPAddress,

		[Parameter(Position=1, ParameterSetName="Host")]
		[Parameter(Position=1, ParameterSetName="IP")]
		[Parameter(Position=1, ParameterSetName="Array")]
		[Alias("Wait","Time")]
		[Timespan]$WaitTime = [Timespan]::FromSeconds(10),

		[Parameter(Position=2, ParameterSetName="Host")]
		[Parameter(Position=2, ParameterSetName="IP")]
		[Parameter(Position=2, ParameterSetName="Array")]
		[Timespan]$Timeout = [Timespan]::FromMinutes(5)
	)

	If ($PSCmdlet.ParameterSetName -eq "Array") {
		$ParamArray.ForEach({
			If ($_ -is "String") {
				If ([String]::IsNullOrEmpty($ResourceName)){
					If ((Validate-IPAddress $_) -or (Validate-HostName $_)) {
						$ResourceName = $_
					} Else {
						Throw "Invalid arguments specified!"
					}
				} Else {
					Throw "Invalid arguments specified!"
				}
			} Else {
				Throw "Invalid arguments specified!"
			}
		})
		If ([String]::IsNullOrEmpty($ResourceName)) {Throw "No resource name specified!"}
	} ElseIf ($PSCmdlet.ParameterSetName -eq "IP") {
		$ResourceName = $IPAddress
	}

	$Timer = [Diagnostics.Stopwatch]::StartNew()
	[Bool]$Out = $True

	# While we cannot establish a connection to the $ResourceName (one ping in quiet mode)
	While (-Not (Test-Connection -ComputerName $ResourceName -Quiet -Count 1)) {
		If ($Timer.Elapsed -ge $Timeout) {
			$Out = $False
			Break
		}
		Start-Sleep -MilliSeconds $WaitTime.TotalMilliseconds
	}

	$Timer.Stop()

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
	# This defaults the parameter set to "None".  It can be forced into "Array" or "Write" by providing an array or one of the write parameters
	[CmdletBinding(DefaultParameterSetName='None')]
	Param (
		# Take an array positionally as the first argument in the "Array" set
		[Parameter(Position=0, Mandatory=$True, ParameterSetName="Array")]
		[ValidateCount(3,8)]
		[Array]$ParamArray,

		# Take a required string as the first argument in the "None" and "Write" sets
		[Parameter(Position=0, Mandatory=$True, ParameterSetName="None")]
		[Parameter(Position=0, Mandatory=$True, ParameterSetName="Write")]
		[Alias("FileName","File","EXE")]
		[ValidateScript({
			# Verify that it's a path that exists and it's not a directory (it's a file)
			If ((Test-Path $_) -and -not ((Get-Item $_) -is [IO.DirectoryInfo])) {
				Return $True
			} Else {
				Throw "Invalid process specified!"
			}
		})]
		[String]$TargetProcess,

		# Take a required string as the second argument in the "None" and "Write" sets
		[Parameter(Position=1, Mandatory=$True, ParameterSetName="None")]
		[Parameter(Position=1, Mandatory=$True, ParameterSetName="Write")]
		[Alias("WorkingDirectory","Directory","Dir")]
		[ValidateScript({
			# Verify that it's a path that exists and it's a directory
			If ((Test-Path $_) -and ((Get-Item $_) -is [IO.DirectoryInfo])) {
				Return $True
			} Else {
				Throw "Invalid start path specified!"
			}
		})]
		[String]$StartDirectory,

		# Take a required string as the third argument in the "None" and "Write" sets
		[Parameter(Position=2, Mandatory=$True, ParameterSetName="None")]
		[Parameter(Position=2, Mandatory=$True, ParameterSetName="Write")]
		# Can be provided using the name VPNResource, Resource, WaitFor, or VPN
		[Alias("Resource","WaitFor","VPN")]
		[String]$VPNResource,

		# Take the As Admin flag in the "None" and "Write" sets
		[Parameter(ParameterSetName="None")]
		[Parameter(ParameterSetName="Write")]
		# Can be provided using the name AsAdmin, Admin, or ADM
		[Alias("Admin","ADM")]
		[Switch]$AsAdmin,

		# Take the Write Out flag in the "Write" set
		[Parameter(ParameterSetName="Write")]
		# Can be provided using the name WriteOut or Write
		[Alias("Write")]
		[Switch]$WriteOut,

		# Take a required string as the 4th parameter in the "Write" set
		[Parameter(ParameterSetName="Write", Mandatory=$True, Position=3)]
		# Can be provided using the name ProcessName or Name
		[Alias("Name")]
		[String]$ProcessName,

		# Take an integer as the 4th parameter in the "None" set or the 5th in the "Write" set, or the second in the "Array" set
		[Parameter(Position=3, ParameterSetName="None")]
		[Parameter(Position=4, ParameterSetName="Write")]
		[Parameter(Position=1, ParameterSetName="Array")]
		# Can be provided using the name WaitTime or CheckTime
		[Alias("CheckTime")]
		# Default to 10 seconds
		[Timespan]$WaitTime = [Timespan]::FromSeconds(10),

		# Take an integer as the 5th parameter in the "None" set or the 6th in the "Write" set, or the third in the "Array" set
		[Parameter(Position=4, ParameterSetName="None")]
		[Parameter(Position=5, ParameterSetName="Write")]
		[Parameter(Position=2, ParameterSetName="Array")]
		# Default to 5 minutes
		[Timespan]$Timeout = [Timespan]::FromMinutes(5),

		# Take an exclusive flag in the "None" and "Write" sets
		[Parameter(ParameterSetName="None")]
		[Parameter(ParameterSetName="Write")]
		# Can be provided using the name Exclusive or Exc
		[Alias("Exc")]
		[Switch]$Exclusive
	)

	# If the parameter array was provided
	If ($PSCmdlet.ParameterSetName -eq "Array") {
		# Iterate through the items in the array
		$ParamArray.ForEach({
			# If the item is a string
			If ($_ -is "String") {
				# If the item is one of the admin flags, set the AsAdmin flag
				If ($_ -in @("-Adm","-Admin","-AsAdmin")) {
					$AsAdmin = $True
				# If the item is one of the write flags, set the WriteOut flag
				} ElseIf ($_ -in @("-Write", "-WriteOut")) {
					$WriteOut = $True
				# If the item is one of the exclusive flags, set the exclusive flag
				} ElseIf ($_ -in @("-Exc","-Exclusive")) {
					$Exclusive  = $True
				# Otherwise
				} Else {
					# If there's no target process and the item is a path that exists and the item is not a directory
					If (([String]::IsNullOrEmpty($TargetProcess)) -and (Test-Path $_) -and -not ((Get-Item $_) -is [IO.DirectoryInfo])) {
						# Set it in the target process
						$TargetProcess = $_
					# If there's no start directory and the item is a path that exists and it's a directory
					} ElseIf (([String]::IsNullOrEmpty($StartDirectory)) -and (Test-Path $_) -and ((Get-Item $_) -is [IO.DirectoryInfo])) {
						# Set it in the start directory
						$StartDirectory = $_
					# If there's no VPN resource
					} ElseIf ([String]::IsNullOrEmpty($VPNResource)) {
						# Set the item in the VPN resource
						$VPNResource = $_
					# If there's no process name
					} ElseIf ([String]::IsNullOrEmpty($ProcessName)) {
						# Set the item in the process name
						$ProcessName = $_
					# Otherwise, throw an error due to invalid input
					} Else {
						Throw "Invalid arguments specified!"
					}
				}
			# If it's not a string but it's an int
			} Else {
				Throw "Invalid arguments specified!"
			}
		})

		# If there's no target process, throw an error
		If ([String]::IsNullOrEmpty($TargetProcess)) {Throw "No target process specified!"}
		# If there's no start directory, throw an error
		If ([String]::IsNullOrEmpty($StartDirectory)) {Throw "No starting directory specified!"}
		# If there's no VPN resource, throw an error
		If ([String]::IsNullOrEmpty($VPNResource)) {Throw "No VPN resource specified!"}
		# If there's no process name and the write flag is set, throw an error
		If ([String]::IsNullOrEmpty($ProcessName) -and $WriteOut) {Throw "No display name specified for the target process!"}
	}

	# If the AsAdmin flag is set
	If ($AsAdmin) {
		# Set the run verb to "RunAs"
		[String]$RunVerb = "RunAs"
	} Else {
		# Otherwise, set it to "Open"
		[String]$RunVerb = "Open"
	}

	# If the write flag is set
	If ($WriteOut) {
		# Write that we're waiting for a connection
		Write-Indirectable "Waiting for connection via VPN..."
	}

	# Use the wait-connect function to wait for a connection to the VPN resource
	If (Wait-Connect $VPNResource -WaitTime $WaitTime -Timeout $Timeout) {
		# If the write flag is set
		If ($WriteOut) {
			# Write that the connection is established and the process is being started
			Write-Indirectable "Connection established."
			Write-Indirectable "Starting $ProcessName executable..."
		}
		# See if the process is already running
		$ProcVar = Get-Process -ErrorAction SilentlyContinue -Name $([IO.Path]::GetFilenameWithoutExtension($TargetProcess))
		# If the process is already running and the exclusive flag was provided
		If ($ProcVar -and $Exclusive) {
			# If the write flag is set, alert the user
			If ($WriteOut) {
				Write-Indirectable "$ProcessName process is already running!"
			}
		} Else {
			# Otherwise, start the appropriate process in the appropriate directory with the appropriate flag.  Store the process in $ProcVar
			$ProcVar = Start-Process -Verb $RunVerb -WorkingDirectory $StartDirectory -FilePath $TargetProcess -PassThru
			# If the write flag is set
			If ($WriteOut) {
				# Write that the process has been started
				Write-Indirectable "$ProcessName executable started."
			}
		}
		# Return a true value
		Return $ProcVar
	# If the wait-connect timed out
	} Else {
		# If the write flag is set
		If ($WriteOut) {
			# Write that the connection failed
			Write-Indirectable "Unable to connect via VPN.  Aborting starting $ProcessName executable."
		}
		# Return false
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
	# This defaults the parameter set to "None".  It can be forced into "Array" by providing an array
	[CmdletBinding(DefaultParameterSetName="None")]
	# Parameter declaration
	Param (
		# Take an array positionally as the first argument in the "Array" set
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="Array")]
		# Only take 2 arguments
		[ValidateCount(2,2)]
		[String[]]$ParamArray,

		# Take a required string as the first argument in the "None" set
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="None")]
		# Can be provided using the name Option, Opt, or O
		[Alias("Opt","O")]
		[String]$Option,

		# Take a required string as the second argument in the "None" set
		[Parameter(Mandatory=$True, Position=1, ParameterSetName="None")]
		# Can be provided using the name Description, Desc, or D
		[Alias("Desc","D")]
		[String]$Description
	)

	# If the parameter array was provided
	If ($PSCmdlet.ParameterSetName -eq "Array") {
		# Store the first argument as the option
		$Option = $ParamArray[0]
		# Store the second argument as the description
		$Description = $ParamArray[1]
	}

	# Return an object for the desired option and description
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
	# Parameter declaration
	Param (
		# Take a required string as the first parameter in the "None" and "Timed" option sets
		[Parameter(Mandatory=$True, Position=0, ParameterSetName='None')]
		[Parameter(Mandatory=$True, Position=0, ParameterSetName='Timed')]
		# Can be provided using the name PromptTitle, Title, or T
		[Alias("Title","T")]
		[String]$PromptTitle,

		# Take a required string as the second parameter in the "None" and "Timed" option sets
		[Parameter(Mandatory=$True, Position=1, ParameterSetName='None')]
		[Parameter(Mandatory=$True, Position=1, ParameterSetName='Timed')]
		# Can be provided using the name PromptQuestion, Question, Message, or Q
		[Alias("Question","Message","Q")]
		[String]$PromptQuestion,

		# Take an array as the third parameter in the "None" and "Timed" option sets
		[Parameter(Position=2, ParameterSetName='None')]
		[Parameter(Position=2, ParameterSetName='Timed')]
		# Can be provided using the name OptionList, Options, Opts, or O
		[Alias("Options","Opts","O")]
		[Array]$OptionList = $(
			New-OptionArray $(New-PromptOption "&Yes" "Message indicating what ""Yes"" will do") $(New-PromptOption "&No" "Message indicating what ""No"" will do")
		),

		# Take an integer as the fourth parameter in the "None" and "Timed" option sets
		[Parameter(Position=3, ParameterSetName='None')]
		[Parameter(Position=3, ParameterSetName='Timed')]
		# Can be provided using the name DefaultOption, Default, Def, or D
		[Alias("Default","Def","D")]
		# Default to 0
		[Int]$DefaultOption = 0,

		# Take a timespan as the fifth parameter in the "Timed" option set
		[Parameter(Position=4, ParameterSetName='Timed')]
		# Default to a timeout of 10 seconds
		[Timespan]$Timeout = [Timespan]::FromSeconds(10),

		# Take a timespan as the sixth parameter in the "Timed" option set
		[Parameter(Position=5, ParameterSetName='Timed')]
		# Default of a timeout of 1 second after pressing a key
		[Timespan]$KeyDelay = [Timespan]::FromSeconds(1),

		# Take a timespan as the seventh parameter in the "Timed" option set
		[Parameter(Position=6, ParameterSetName='Timed')]
		# Default to checking for keys every 1/10th of a second (100 ms)
		[Timespan]$CheckInt = [Timespan]::FromMilliseconds(100),

		# Take a switch parameter in the "Timed" option set, for easy switching to timed mode
		[Parameter(ParameterSetName='Timed')]
		[Switch]$Timed
	)

	# If not in the timed parameter set, use $Host.UI.PromptForChoice for a prompt with no timeout
	If (!$Timed) {
		# This function is essentially a macro.  Run the command to prompt the user given the provided options and Return the output.
		Return $Host.UI.PromptForChoice( $PromptTitle, $PromptQuestion, $OptionList, $DefaultOption )
	} Else {
		# Create a function to write the prompt text, with the default option in yellow
		Function Write-Prompt {
			Param(
				# Take an array of strings to write
				[String[]]$Pstr,
				# And a switch to avoid writing a newline afterwards
				[Switch] $NoNewLine
			)

			# Write the first element in the array in white (before the default)
			If ([bool]$Pstr[0]) {
				Write-Indirectable -NoNewLine $Pstr[0]
			}
			# Write the second element in the array (the default) in yellow
			Write-Indirectable -NoNewLine -ForegroundColor Yellow $Pstr[1]
			# Then write the last element in the array in white (after the default)
			# If the NoNewLine parameter was provided, don't write a newline afterwards
			Write-Indirectable -NoNewLine:$NoNewLine $Pstr[2]
		}

		If ($DefaultOption -ge $OptionList.Length) {
			# Re-run in un-timed mode to throw the correct error
			Return Select-Option $PromptTitle $PromptQuestion $OptionList $DefaultOption
		}

		# Write a newline
		Write-Indirectable ""
		# Write the title
		Write-Indirectable $PromptTitle
		# Write the question
		Write-Indirectable $PromptQuestion

		# Create an empty hashtable to hold valid inputs
		$Map = @{}
		# Create a new arraylist for an array-like object which can easily be appended to
		$Disp = New-Object System.Collections.ArrayList
		# Create a 3-element array to hold the prompt string
		# Use arraylists for performance when appending elements
		$Pstr = @($(New-Object System.Collections.ArrayList),$(New-Object System.Collections.ArrayList),$(New-Object System.Collections.ArrayList))
		# Start indexing at 0
		$Index = 0
		# Iterate through the provided option list
		ForEach ($Item in $OptionList) {
			# Strip ampersands from the item label for the long input
			$Long = $Item.Label.Replace("&","")
			# Short input is null for now
			$Short = ""
			# If the label contains an ampersand
			If ($Item.Label.Contains("&")) {
				# The short label is the caracter after the ampersand
				$Short = [String]$Item.Label[$Item.Label.IndexOf("&") + 1]
				# Map the short label to the index number
				$Map[$Short] = $Index
				# Add the short label with the help message to the help array
				# Have to store the output to consume it
				$Null = $Disp.Add(@($Short, $Item.HelpMessage))
			} Else {
				# If no ampersand, add the long label and the help message to the help array
				$Null = $Disp.Add(@($Long, $Item.HelpMessage))
			}
			# If the index is less than the default, add the option to the pre-default element in the prompt string array
			# If the index is greater than the default, add the option to the post-default element
			# And if the index is equal to the default, add the option to the default element
			$Null = $Pstr[(($Index -ge $DefaultOption) + ($Index -gt $DefaultOption))].add("[$Short] $Long")
			# Map the long label to the index number and increment the index number
			$Map[$Long] = $Index++
		}
		# If the default option contains an ampersand
		If ($OptionList[$DefaultOption].Label.Contains("&")) {
			# Store the short label as the default option
			$DefOp = $OptionList[$DefaultOption].Label[$OptionList[$DefaultOption].Label.IndexOf("&") + 1]
		} Else {
			# Otherwise, store the long label
			$DefOp = $OptionList[$DefaultOption].Label.Replace("&","")
		}
		# If ? is used as a key
		If ($Map.ContainsKey("?")) {
			# Re-run in un-timed mode to throw the correct error
			Return Select-Option $PromptTitle $PromptQuestion $OptionList $DefaultOption
		}
		# If first element isn't default, append a space
		If ($Pstr[0]) {
			$Null = $Pstr[0].Add(" ")
		}
		# Default option is always present
		$Null = $Pstr[1].Add(" ")
		# Append the help message to the post-default element in the prompt string array
		$Null = $Pstr[2].Add("[?] Help (default is ""$DefOp""): ")

		# And write the prompt string array (the options) with the default in yellow
		# Don't include a trailing newline
		Write-Prompt -NoNewLine $Pstr

		# Start a pair of timers
		$Timer = [Diagnostics.StopWatch]::StartNew()
		$Last = [Diagnostics.StopWatch]::StartNew()
		# Flush the input buffer
		$Host.UI.RawUI.FlushInputBuffer()
		# Start the input as an empty string
		$Inp = ""
		# As long as we haven't exceeded the timeout, or we've pressed a key recently enough
		While (($Timer.Elapsed -lt $Timeout) -or ($Last.Elapsed -lt $KeyDelay)) {
			# Check to see if there's a key available
			If ([Console]::KeyAvailable) {
				# If there is, grab the key but don't echo it
				$Key = [Console]::ReadKey($True)
				# If the key has a character and it's not a control character
				If ($Key.KeyChar -and ($Key.KeyChar -NotMatch "\p{C}")) {
					# Write the character
					Write-Indirectable -NoNewLine $Key.KeyChar
					# Add the character to the input
					$Inp += [String]$Key.KeyChar
					# Restart the keystroke timer
					$Last.Restart()
				# If the key is a backspace
				} ElseIf (($Key.Key -eq "Backspace") -and ($Inp -ne '')){
					# Move the cursor back, overwrite the last character with a space, then move the cursor back again
					Write-Indirectable -NoNewLine "$([Char]8) $([Char]8)"
					# Remove the last character from the input string
					$Inp = $Inp -Replace ".$"
					# Restart the keystroke timer
					$Last.Restart()
				# If the key is a carriage return
				} ElseIf ($Key.Key -eq "Enter") {
					# Write a newline
					Write-Indirectable ""
					# If the input is exactly a question mark
					If ("?" -eq $Inp) {
						# Write out each of the help options stored earlier
						ForEach ($Option in $Disp) {
							Write-Indirectable "$($Option[0]) - $($Option[1])"
						}
					# If the input is in the map
					} ElseIf ($Map.ContainsKey($Inp)) {
						# Return the index of the input
						Return $Map[$Inp]
					# If the input is null
					} ElseIf ('' -eq $Inp) {
						# Return the default index
						Return $DefaultOption
					# If the input isn't ?, isn't in the map, and isn't null
					}
					# Reset the input string
					$Inp = ""
					# Restart the timers
					$Timer.Restart()
					$Last.Restart()
					# Then re-write the prompt
					Write-Prompt -NoNewLine $Pstr
				}
			} Else {
				# If there's no key available, check back after the check interval
				Start-Sleep -Milliseconds $CheckInt.TotalMilliseconds
			}
		}
		# If the function has gotten this far, we've exceeded the timeout
		# Write a newline
		Write-Indirectable ""
		# If they entered a valid key and just failed to hit enter, take that
		# Otherwise, return -1
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
	# Parameter declaration
	Param(
		# Take one parameter, the text to be written
		# Take all parameters provided as the text
		[Parameter(ValueFromRemainingArguments=$True)]
		[String]$Text,

		# Take a flag to left-truncate the text
		[Alias("Truncate","Trunc", "LT")]
		[Switch]$LeftTruncate,

		# Take a flag to right-truncate the text
		[Alias("RTruncate","RTrunc","RT")]
		[Switch]$RightTruncate
	)

	# Get the current X position of the cursor
	[Int]$X = $Host.UI.RawUI.CursorPosition.X
	# Get the window width
	# The cursor never actually moves to the final position in the window, so subtract one to keep everything lined up
	[Int]$Width = $Host.UI.RawUI.WindowSize.Width-1
	# Instantiate an AfterText variable as null
	[String]$AfterText = ""

	# If the string is long enough that it will exceed the width
	If ($Text.Length -gt $Width) {
		# If the LeftTruncate flag is set
		If ($LeftTruncate) {
			# Get the substring starting at Length-Width characters (Keep $Width characters on the right)
			$Text = $Text.Substring($Text.Length-$Width)
		# Otherwise, if the RightTruncate flag is set
		} ElseIf ($RightTruncate) {
			# Remove all characters after the $Width
			$Text = $Text.Remove($Width)
		}
	}

	# If the text won't completely overwrite the previous contents of the line
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
	Write-Indirectable -NoNewLine "$([String][Char]8*$X)$Text$AfterText"
}

Function Wait-ProcessRam {
	<#
		Wait for a process to hit a specified number of RAM handles.  Optionally restart it if it stalls at the same number of RAM handles for a specified period of time.  Optionally, it will wait for a process with the specified name to start
	#>
	# This defaults the parameter set to "Name".  It can be forced into "Proc", "WriteName" or "WriteProc" by providing parameters included in one of these sets
	[CmdletBinding(DefaultParameterSetName="Name")]
	# Parameter declaration
	Param(
		# Take a string that's the name of the process to look for as the first parameter in the "Name", "WriteName", "NameRestart" and "WriteNameRestart" sets
		[Parameter(Position=0, Mandatory=$True, ParameterSetName="Name")]
		[Parameter(Position=0, Mandatory=$True, ParameterSetName="WriteName")]
		[Parameter(Position=0, Mandatory=$True, ParameterSetName="NameRestart")]
		[Parameter(Position=0, Mandatory=$True, ParameterSetName="WriteNameRestart")]
		[Alias("Name","PN")]
		[String]$ProcessName,

		# Take a process to wait for as the first parameter in the "Proc", "WriteProc", "ProcRestart", and "WriteProcRestart" sets
		[Parameter(Position=0, Mandatory=$True, ParameterSetName="Proc")]
		[Parameter(Position=0, Mandatory=$True, ParameterSetName="WriteProc")]
		[Parameter(Position=0, Mandatory=$True, ParameterSetName="ProcRestart")]
		[Parameter(Position=0, Mandatory=$True, ParameterSetName="WriteProcRestart")]
		[Alias("Proc")]
		[Diagnostics.Process]$Process,

		# Take an integer representing the RAM handles to wait for as the second parameter
		[Parameter(Position=1, Mandatory=$True)]
		[Alias("Handles","HandleCount")]
		[Int]$HandleStop,

		# Take a tolerance level for the RAM handles.  If the RAM handles does not change by more than the tolerance, consider it unchanged
		[Alias("Tol")]
		[Int]$Tolerance = 3,

		# Take a switch to force the function into one of the "Write" sets
		[Parameter(ParameterSetName="WriteName")]
		[Parameter(ParameterSetName="WriteProc")]
		[Parameter(ParameterSetName="WriteNameRestart")]
		[Parameter(ParameterSetName="WriteProcRestart")]
		[Alias("Write")]
		[Switch]$WriteOut,

		# Take a string to display as the process name as the third parameter in the "Write" sets
		[Parameter(Position=2, Mandatory=$True, ParameterSetName="WriteName")]
		[Parameter(Position=2, Mandatory=$True, ParameterSetName="WriteProc")]
		[Parameter(Position=2, Mandatory=$True, ParameterSetName="WriteNameRestart")]
		[Parameter(Position=2, Mandatory=$True, ParameterSetName="WriteProcRestart")]
		[Alias("Display","WN")]
		[String]$WriteName,

		# Take a timespan representing the time after which to assume the process is stuck as the fourth paramter
		[Parameter(Position=3)]
		[Alias("Timeout")]
		[Timespan]$StuckTime = [Timespan]::FromSeconds(30),

		# Take a timespan represnting the time to wait between RAM handle checks as the 5th parameter
		[Parameter(Position=4)]
		[Alias("CheckInt","Check")]
		[Timespan]$CheckInterval = [Timespan]::FromMilliseconds(100),

		# Take a switch in the "Name" sets to cause the function to wait for the process to start if it's not running
		[Parameter(ParameterSetName="Name")]
		[Parameter(ParameterSetName="WriteName")]
		[Parameter(ParameterSetName="NameRestart")]
		[Parameter(ParameterSetName="WriteNameRestart")]
		[Alias("Wait")]
		[Switch]$WaitStart,

		# Take a timespan as the 6th parameter in the "Name" sets representing the time to wait between checks to see if the process is running
		[Parameter(Position=5, ParameterSetName="Name")]
		[Parameter(Position=5, ParameterSetName="WriteName")]
		[Parameter(Position=5, ParameterSetName="NameRestart")]
		[Parameter(Position=5, ParameterSetName="WriteNameRestart")]
		[Alias("WaitTime","WI")]
		[Timespan]$WaitInterval = [Timespan]::FromSeconds(1),

		# Take a timespan as the 7th parameter in the "Name" sets representing the time after which to abort waiting for the process to start
		[Parameter(Position=6, ParameterSetName="Name")]
		[Parameter(Position=6, ParameterSetName="WriteName")]
		[Parameter(Position=6, ParameterSetName="NameRestart")]
		[Parameter(Position=6, ParameterSetName="WriteNameRestart")]
		[Alias("WT")]
		[Timespan]$WaitTimeout = [Timespan]::FromMinutes(5),

		# Take a flag to cause the function to restart a stalled process in the "Restart"
		[Parameter(ParameterSetName="NameRestart")]
		[Parameter(ParameterSetName="WriteNameRestart")]
		[Parameter(ParameterSetName="ProcRestart")]
		[Parameter(ParameterSetName="WriteProcRestart")]
		[Switch]$Restart,

		# Take a mandatory script block to execute in order to start the process after killing it as the 8th parameter in the "Restart" sets
		[Parameter(Position=7, Mandatory=$True, ParameterSetName="NameRestart")]
		[Parameter(Position=7, Mandatory=$True, ParameterSetName="WriteNameRestart")]
		[Parameter(Position=7, Mandatory=$True, ParameterSetName="ProcRestart")]
		[Parameter(Position=7, Mandatory=$True, ParameterSetName="WriteProcRestart")]
		[Alias("Script","RS")]
		[Management.Automation.ScriptBlock]$RestartScript,

		# Take a handle count under which the process should not be restarted
		[Parameter(Position=8, Mandatory=$True, ParameterSetName="NameRestart")]
		[Parameter(Position=8, Mandatory=$True, ParameterSetName="WriteNameRestart")]
		[Parameter(Position=8, Mandatory=$True, ParameterSetName="ProcRestart")]
		[Parameter(Position=8, Mandatory=$True, ParameterSetName="WriteProcRestart")]
		[Alias("StartAt","LowStop","Start")]
		[Int]$StartCount,

		# Take a switch to start high and wait for a low, rather than starting low and waiting for a high
		[Switch]$Low,

		# Take a switch to avoid waiting the first interval in the event that the target has already hit the desired RAM handle count
		[Switch]$NoWait
	)

	# If we're in one of the "Name" parameter sets
	If ($PSCmdlet.ParameterSetName -like "*Name*") {
		# Use Get-Process to find the running executable
		$Process = Get-Process -ErrorAction SilentlyContinue -Name $ProcessName
		# If there's no process and we're waiting for the process to start
		If (!$Process -and $WaitStart) {
			# If writing output, alert the user
			If ($WriteOut) {
				Write-Indirectable "$WriteName process is not running.  Waiting for process to start..."
			}
			# Start a timer
			$Timer = [Diagnostics.Stopwatch]::StartNew()
			# While there's no process to watch
			While (!$Process) {
				# If the timeout has elapsed
				If ($Timer.Elapsed -ge $WaitTimeout) {
					# Alert the user and break the loop
					Write-Indirectable "Timeout has expired!"
					Break
				}
				# Sleep for the wait interval
				Start-Sleep -Milliseconds $WaitInterval.TotalMilliseconds
				# Search for the process again
				$Process = Get-Process -ErrorAction SilentlyContinue -Name $ProcessName
			}
			# Stop the timer
			$Timer.Stop()
		}
		# If there's no process, throw an error
		If (!$Process) {
			Throw "Process not found!"
		}
		# If writing output, alert the user that the process is running
		If ($WriteOut) {
			Write-Indirectable "$writename process is running."
		}
	# Otherwise, if we're in one of the "Proc" sets
	} Else {
		# If the user did not specify a process or if it exited, throw an error
		If (!$Process -or $Process.HasExited) {
			Throw "Invalid process specified!"
		}
	}

	# If writing output, alert the user that we're waiting for the process
	If ($WriteOut) {
		Write-Indirectable "Waiting for $WriteName process.  RAM Handles count:"
	}

	# If the loop is already going to terminate, and we've got a NoWait flag
	# This is a simplified version of (Not (loop continue condition) and $NoWait)
	If ($NoWait -and (($Process.HandleCount -ge $HandleStop) -or $Low) -and !(($Process.HandleCount -gt $HandleStop) -and $Low)) {
		# Set the check interval to 0 (don't pause during the loop)
		$CheckInterval = New-Timespan
	}

	# Start a timer
	$Timer = [Diagnostics.Stopwatch]::StartNew()
	# Start a loop
	Do {
		# If writing output, display the current RAM handle count and the change in the last 30 seconds
		If ($WriteOut) {
			Write-Update "$($Process.HandleCount) / $HandleStop ($([Math]::Abs($LastHandleCount - $Process.HandleCount)) change in the last $([Int]$Timer.Elapsed.TotalSeconds) seconds)"
		}
		# If the handle count is within the tolerance since the last update
		If ([Math]::Abs($LastHandleCount - $Process.HandleCount) -lt $Tolerance) {
			# Set a flag indicating whether or not to restart based on the RAM handle count (if it's on the wrong side of StartCount, don't restart)
			[Bool]$RestartTest = ((($Process.HandleCount -lt $StartCount) -and $Low) -or (($Process.HandleCount -gt $StartCount) -and !$Low))
			# If the stuck time has been exceeded, the reset flag is set, and the handle count is on the right side of StartCount
			If (($Timer.Elapsed -ge $StuckTime) -and $Restart -and $RestartTest) {
				# If writing output, alert the user that the process is stuck and it's being terminated
				If ($WriteOut) {
					Write-Update "$WriteName process appears to be stuck at $($Process.HandleCount) RAM handles!"
					Write-Indirectable ""
					Write-Indirectable "Terminating $WriteName process..."
				}
				# Kill the process
				$Process.Kill()
				# Execute the restart script provided
				$Process = .$RestartScript
				# If the restart script did not return a process, throw an error
				If (!$Process) {
					Throw "Unable to keep track of $WriteName process!  Restart script must return a process object!"
				}
				# If writing output, alert the user that we're waiting for the process
				If ($WriteOut) {
					Write-Indirectable "Waiting for $WriteName process.  RAM handles count:"
				}
			}
		# If the RAM handle count is different than last check
		} Else {
			# Reset the timer
			$Timer.Restart()
		}
		# Store the last handle count, if the change has exceeded the tolerance
		If ([Math]::Abs($LastHandleCount - $Process.HandleCount) -ge $Tolerance) {
			$LastHandleCount = $Process.HandleCount
		}
		# Sleep for the check interval
		Start-Sleep -Milliseconds $CheckInterval.TotalMilliseconds
		# Refresh the process information
		$Process.Refresh()
		# If the process has stopped
		If ($Process.HasExited) {
			# If writing output, alert the user
			If ($WriteOut) {
				Write-Indirectable ""
				Write-Indirectable "$WriteName process has exited."
			}
			# Return false
			Return $False
		}
	# Loop While the handle count is lower than desired (or higher than desired, if the Low flag was provided)
	} While ((($Process.HandleCount -lt $HandleStop) -and !$Low) -or (($Process.HandleCount -gt $HandleStop) -and $Low))

	# If writing output, alert the user that the desired RAM handle count has been reached
	If ($WriteOut) {
		Write-Indirectable ""
		Write-Indirectable "$WriteName process has reached $HandleStop RAM handles."
	}

	# Return true
	Return $True
}

Function Wait-ProcessIdle {
	# This defaults the parameter set to "Name".  It can be forced into "Proc", "WriteName" or "WriteProc" by providing parameters included in one of these sets
	[CmdletBinding(DefaultParameterSetName="Name")]
	# Parameter Declaration
	Param(
		# Take a string that's the name of the process to look for as the first parameter in the "Name" and "WriteName" sets
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="Name")]
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="WriteName")]
		[Alias("Name","PN")]
		[String]$ProcessName,

		# Take a process to wait for as the first parameter in the "Proc" and "WriteProc" sets
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="Proc")]
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="WriteProc")]
		[Alias("Proc")]
		[Diagnostics.Process]$Process,

		# Take a timespan indicating how long the program must be idle for as the second parameter
		[Parameter(Position=1)]
		[Alias("Stable","Idle","IdleTime")]
		[Timespan]$StableTime = [Timespan]::FromMilliseconds(500),

		# Take a timespan indicating how frequently to check CPU time as the third parameter
		[Parameter(Position=2)]
		[Alias("CheckInt","Check")]
		[Timespan]$CheckInterval = [Timespan]::FromMilliseconds(100),

		# Take a switch in the "Name" sets to cause the function to wait for the process to start if it's not running
		[Parameter(ParameterSetName="Name")]
		[Parameter(ParameterSetName="WriteName")]
		[Alias("Wait")]
		[Switch]$WaitStart,

		# Take a timespan as the 4th parameter in the "Name" sets representing the time to wait between checks to see if the process is running
		[Parameter(Position=3, ParameterSetName="Name")]
		[Parameter(Position=3, ParameterSetName="WriteName")]
		[Alias("WaitTime","WI")]
		[Timespan]$WaitInterval = [Timespan]::FromSeconds(1),

		# Take a timespan as the 5th parameter in the "Name" sets representing the time after which to abort waiting for the process to start
		[Parameter(Position=4, ParameterSetName="Name")]
		[Parameter(Position=4, ParameterSetName="WriteName")]
		[Alias("WT")]
		[Timespan]$WaitTimeout = [Timespan]::FromSeconds(120),

		# Take a switch to force the function into one of the "Write" sets
		[Parameter(ParameterSetName="WriteName")]
		[Parameter(ParameterSetName="WriteProc")]
		[Alias("Write")]
		[Switch]$WriteOut,

		# Take a string to display as the process name as the 6th parameter in the "Write" sets
		[Parameter(Mandatory=$True, Position=5, ParameterSetName="WriteName")]
		[Parameter(Mandatory=$True, Position=5, ParameterSetName="WriteProc")]
		[Alias("Display","WN")]
		[String]$WriteName
	)

	# If we're in one of the "Name" parameter sets
	If ($PSCmdlet.ParameterSetName -like "*Name") {
		# Use Get-Process to find the running executable
		$Process = Get-Process -ErrorAction SilentlyContinue -Name $ProcessName
		# If there's no process and we're waiting for the process to start
		If (!$Process -and $WaitStart) {
			# If writing output, alert the user
			If ($WriteOut) {
				Write-Indirectable "$WriteName process is not running.  Waiting for process to start..."
			}
			# Start a timer
			$Timer = [Diagnostics.Stopwatch]::StartNew()
			# While there's no process to watch
			While (!$Process) {
				# If the timeout has elapsed
				If ($Timer.Elapsed -ge $WaitTimeout) {
					# Alert the user and break the loop
					Write-Indirectable "Timeout has expired!"
					Break
				}
				# Sleep for the wait interval
				Start-Sleep -Milliseconds $WaitInterval.TotalMilliseconds
				# Search for the process again
				$Process = Get-Process -ErrorAction SilentlyContinue -Name $ProcessName
			}
			# Stop the timer
			$Timer.Stop()
		}
		# If there's no process, throw an error
		If (!$Process) {
			Throw "Process not found!"
		}
		# If writing output, alert the user that the process is running
		If ($WriteOut) {
			Write-Indirectable "$writename process is running."
		}
	# Otherwise, if we're in one of the "Proc" sets
	} Else {
		# If the user did not specify a process or if it exited, throw an error
		If (!$Process -or $Process.HasExited) {
			Throw "Invalid process specified!"
		}
	}

	# If writing output, alert the user that we're waiting for the process
	If ($WriteOut) {
		Write-Indirectable "Waiting for $WriteName process to idle..."
	}

	# Wait for the process to start getting time on the CPU
	While ($Process.CPU -eq 0) {
		# Sleep for the check interval
		Start-Sleep -Milliseconds $CheckInterval.TotalMilliseconds
		# Refresh the process information
		$Process.Refresh()
		# If the process has exited
		If ($Process.HasExited) {
			# If writing output, alert the user
			If ($WriteOut) {
				Write-Indirectable "$WriteName process has exited."
			}
			# Return false
			Return $False
		}
	}

	# Start the last CPU time at -1, because it's impossible to match that initially - this ensures that the process will be idle for the full idle time
	$LastCPU = -1
	# Start a timer
	$Timer = [Diagnostics.Stopwatch]::StartNew()
	# Loop while the idle time has not elapsed
	While ($Timer.Elapsed -le $StableTime) {
		# If the current CPU time doesn't match the last CPU time
		If ($Process.CPU -ne $LastCPU) {
			# Restart the idle timer
			$Timer.Restart()
			# Update the last CPU time
			$LastCPU = $Process.CPU
		}
		# Sleep for the check interval
		Start-Sleep -Milliseconds $CheckInterval.TotalMilliseconds
		# Refresh the process information
		$Process.Refresh()
		# If the process has stopped
		If ($Process.HasExited) {
			# If writing output, alert the user
			If ($WriteOut) {
				Write-Indirectable "$WriteName process has exited."
			}
			# Return false
			Return $False
		}
	}

	# If writing output, alert the user that the process has idled for the requisite time
	If ($WriteOut) {
		Write-Indirectable "$WriteName process has idled."
	}
	# Return true
	Return $True
}

Function Wait-ProcessMainWindow {
	# This defaults the parameter set to "Name".  It can be forced into "Proc", "WriteName" or "WriteProc" by providing parameters included in one of these sets
	[CmdletBinding(DefaultParameterSetName="Name")]
	# Parameter Declaration
	Param(
		# Take a string that's the name of the process to look for as the first parameter in the "Name" and "WriteName" sets
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="Name")]
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="WriteName")]
		[Alias("Name","PN")]
		[String]$ProcessName,

		# Take a process to wait for as the first parameter in the "Proc" and "WriteProc" sets
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="Proc")]
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="WriteProc")]
		[Alias("Proc")]
		[Diagnostics.Process]$Process,

		# Take a pointer indicating the original window handle
		[Parameter(Position=1)]
		[Alias("Handle","OH")]
		[IntPtr]$OriginalHandle = 0,

		# Take a timespan indicating how frequently to check CPU time as the third parameter
		[Parameter(Position=2)]
		[Alias("CheckInt","Check")]
		[Timespan]$CheckInterval = [Timespan]::FromMilliseconds(100),

		# Take a switch in the "Name" sets to cause the function to wait for the process to start if it's not running
		[Parameter(ParameterSetName="Name")]
		[Parameter(ParameterSetName="WriteName")]
		[Alias("Wait")]
		[Switch]$WaitStart,

		# Take a timespan as the 4th parameter in the "Name" sets representing the time to wait between checks to see if the process is running
		[Parameter(Position=3, ParameterSetName="Name")]
		[Parameter(Position=3, ParameterSetName="WriteName")]
		[Alias("WaitTime","WI")]
		[Timespan]$WaitInterval = [Timespan]::FromSeconds(1),

		# Take a timespan as the 5th parameter in the "Name" sets representing the time after which to abort waiting for the process to start
		[Parameter(Position=4, ParameterSetName="Name")]
		[Parameter(Position=4, ParameterSetName="WriteName")]
		[Alias("WT")]
		[Timespan]$WaitTimeout = [Timespan]::FromSeconds(120),

		# Take a switch to force the function into one of the "Write" sets
		[Parameter(ParameterSetName="WriteName")]
		[Parameter(ParameterSetName="WriteProc")]
		[Alias("Write")]
		[Switch]$WriteOut,

		# Take a string to display as the process name as the 6th parameter in the "Write" sets
		[Parameter(Mandatory=$True, Position=5, ParameterSetName="WriteName")]
		[Parameter(Mandatory=$True, Position=5, ParameterSetName="WriteProc")]
		[Alias("Display","WN")]
		[String]$WriteName
	)

	# If we're in one of the "Name" parameter sets
	If ($PSCmdlet.ParameterSetName -like "*Name") {
		# Use Get-Process to find the running executable
		$Process = Get-Process -ErrorAction SilentlyContinue -Name $ProcessName
		# If there's no process and we're waiting for the process to start
		If (!$Process -and $WaitStart) {
			# If writing output, alert the user
			If ($WriteOut) {
				Write-Indirectable "$WriteName process is not running.  Waiting for process to start..."
			}
			# Start a timer
			$Timer = [Diagnostics.Stopwatch]::StartNew()
			# While there's no process to watch
			While (!$Process) {
				# If the timeout has elapsed
				If ($Timer.Elapsed -ge $WaitTimeout) {
					# Alert the user and break the loop
					Write-Indirectable "Timeout has expired!"
					Break
				}
				# Sleep for the wait interval
				Start-Sleep -Milliseconds $WaitInterval.TotalMilliseconds
				# Search for the process again
				$Process = Get-Process -ErrorAction SilentlyContinue -Name $ProcessName
			}
			# Stop the timer
			$Timer.Stop()
		}
		# If there's no process, throw an error
		If (!$Process) {
			Throw "Process not found!"
		}
		# If writing output, alert the user that the process is running
		If ($WriteOut) {
			Write-Indirectable "$writename process is running."
		}
	# Otherwise, if we're in one of the "Proc" sets
	} Else {
		# If the user did not specify a process or if it exited, throw an error
		If (!$Process -or $Process.HasExited) {
			Throw "Invalid process specified!"
		}
	}

	# If writing output, alert the user that we're waiting for the main window handle
	If ($WriteOut) {
		Write-Indirectable "Waiting for $WriteName process main window handle to change..."
	}

	# Loop while the main window handle has not changed
	While ($Process.MainWindowHandle -eq $OriginalHandle) {
		# Sleep for the check interval
		Start-Sleep -Milliseconds $CheckInterval.TotalMilliseconds
		# Refresh the process information
		$Process.Refresh()
		# If the process has stopped
		If ($Process.HasExited) {
			# If writing output, alert the user
			If ($WriteOut) {
				Write-Indirectable "$WriteName process has exited."
			}
			# Return false
			Return $False
		}
	}

	# If writing output, alert the user to the updated main window handle
	If ($WriteOut) {
		Write-Indirectable "$WriteName process main window handle is now $($Process.MainWindowHandle)."
	}
	# Return true
	Return $True
}

Function Wait-ProcessClose {
	# This defaults the parameter set to "Name".  It can be forced into "Proc", "WriteName" or "WriteProc" by providing parameters included in one of these sets
	[CmdletBinding(DefaultParameterSetName="Name")]
	# Parameter Declaration
	Param(
		# Take a string that's the name of the process to look for as the first parameter in the "Name" and "WriteName" sets
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="Name")]
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="WriteName")]
		[Alias("Name","PN")]
		[String]$ProcessName,

		# Take a process to wait for as the first parameter in the "Proc" and "WriteProc" sets
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="Proc")]
		[Parameter(Mandatory=$True, Position=0, ParameterSetName="WriteProc")]
		[Alias("Proc")]
		[Diagnostics.Process]$Process,

		# Take a timespan indicating how frequently to check the process
		[Parameter(Position=1)]
		[Alias("CheckInt","Check")]
		[Timespan]$CheckInterval = [Timespan]::FromMilliseconds(100),

		# Take a timespan indicating the maximum time to wait
		[Parameter(Position=2)]
		[Alias("Time")]
		[Timespan]$Timeout = [Timespan]::FromMinutes(2),

		# Take a switch to force the function into one of the "Write" sets
		[Parameter(ParameterSetName="WriteName")]
		[Parameter(ParameterSetName="WriteProc")]
		[Alias("Write")]
		[Switch]$WriteOut,

		# Take a string to display as the process name as the 6th parameter in the "Write" sets
		[Parameter(Mandatory=$True, Position=3, ParameterSetName="WriteName")]
		[Parameter(Mandatory=$True, Position=3, ParameterSetName="WriteProc")]
		[Alias("Display","WN")]
		[String]$WriteName
	)

	# If we're in one of the "Name" parameter sets
	If ($PSCmdlet.ParameterSetName -like "*Name") {
		# Use Get-Process to find the running executable
		$Process = Get-Process -ErrorAction SilentlyContinue -Name $ProcessName
	# Otherwise, if we're in one of the "Proc" sets
	}

	# If the user did not specify a process or if it exited, return true
	If (!$Process -or $Process.HasExited) {
		If ($WriteOut) {
			Write-Indirectable "$WriteName process has exited."
			Return $True
		}
	}

	# If writing output, alert the user that we're waiting for the process
	If ($WriteOut) {
		Write-Indirectable "Waiting for $WriteName process to exit..."
	}

	# Start a timer
	$Timer = [Diagnostics.Stopwatch]::StartNew()
	# Loop while the idle time has not elapsed
	While (!($Process.HasExited)) {
		# Sleep for the check interval
		Start-Sleep -Milliseconds $CheckInterval.TotalMilliseconds
		# Refresh the process information
		$Process.Refresh()
		# If the process has stopped
		If ($Timer.Elapsed -ge $Timeout) {
			# If writing output, alert the user
			If ($WriteOut) {
				Write-Indirectable "Timeout exceeded."
				Write-Indirectable "$WriteName process has not exited."
			}
			# Return false
			Return $False
		}
	}

	# If writing output, alert the user that the process has idled for the requisite time
	If ($WriteOut) {
		Write-Indirectable "$WriteName process has exited."
	}
	# Return true
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
		[Timespan]$Timeout = [Timespan]::FromSeconds(30),
		
		[String] $Path = ""
	)

	If ($PSCmdlet.ParameterSetName -like "*Name") {
		If ($WriteOut) {
			Write-Indirectable "Acquiring handle for $WriteName process..."
		}
		$Process = Get-Process -ErrorAction SilentlyContinue -Name $ProcessName
	}

	If (!$Process -or $Process.HasExited) {
		Throw "Invalid process specified!"
	}

	If (!$Path) {
		$Path = $Process.Path
	}

	If ($UseExternal) {
		If ($WriteOut) {
			Write-Indirectable "Stopping $WriteName process using external command: ""$External""..."
		}
		cmd /c "$External"
	} ElseIf ($UseFlags) {
		If ($WriteOut) {
			Write-Indirectable "Stopping $WriteName process using flags: ""$Flags""..."
		}
		Start-Process $Path -ArgumentList $Flags
	} Else {
		If ($WriteOut) {
			Write-Indirectable "Stopping $WriteName process by closing main window..."
		}
		$Process.CloseMainWindow()
	}

	If ($ForceClose -and !$(Wait-ProcessClose $Process -WriteOut:$WriteOut -WriteName $WriteName -CheckInterval $CheckInterval -Timeout $Timeout)) {
		If ($WriteOut) {
			Write-Indirectable "$WriteName process is not stopping.  Force closing..."
		}
		$Process.Kill()
		$ForceClose = $False
	}
	If (!$ForceClose -and !$(Wait-ProcessClose $Process -WriteOut:$WriteOut -WriteName $WriteName -CheckInterval $CheckInterval -Timeout $Timeout)) {
		If ($WriteOut) {
			Write-Indirectable "Unable to stop $WriteName process!"
		}
		Return $False
	}

	If ($WriteOut -and $StartArgs) {
		Write-Indirectable "Starting $WriteName process with arguments ""$StartArgs""..."
	} ElseIf ($WriteOut) {
		Write-Indirectable "Starting $WriteName process..."
	}

	If ($StartArgs) {
		Start-Process $Path -ArgumentList $StartArgs
	} Else {
		Start-Process $Path
	}

	If ($WriteOut) {
		Write-Indirectable "$WriteName process started."
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
				Write-Indirectable "`r`n"
				Write-Indirectable "Type $TypeName contains the following objects:"
				Write-Indirectable $GroupStr
				Write-Indirectable "Members of ${TypeName}:"
				Write-Indirectable $DispStr
			}

		}
	} Else {
		ForEach ($Entry in $Output) {
			$Indent = $Entry[0]
			Write-Indirectable "`r`n"
			Write-Indirectable $(Format-String $Entry[1] -Indent $Indent)
			$Disparray = $Entry[2]
			$Indent += 2
			if ($NoTruncate) {
				Write-Indirectable $(Format-String -Trim -Indent $Indent @DispArray)
			} Else {
				Write-Indirectable $(Format-String -Trim -Indent $Indent -Truncate -Width $Width @DispArray)
			}
		}
	}
}

Function Wait-AnyKey {
	# Check if running Powershell ISE
	If ($psISE) {
		Add-Type -AssemblyName System.Windows.Forms
		[System.Windows.Forms.MessageBox]::Show("Press any key to continue...")
	} Else {
		Write-Indirectable -NoNewLine "Press any key to continue..."
		$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
		Write-Indirectable ""
	}
}

Function Restart-Script {
	Param(
		[Parameter(Position=0)]
		[String]$CommandPath,
		
		[Parameter(Position=1)]
		[HashTable]$ArgumentList,
		
		[Switch]$Admin,
		
		[Switch]$NoExit,
		
		[Switch]$Hidden
	)
	# Syntax: Restart-Script $PSCommandPath $PSBoundParameters [-Admin] [-NoExit] [-Hidden]
	$SapsArgs = @{
		"FilePath" = $(Get-Process -Id $PID).Path
		"ArgumentList" = "-ExecutionPolicy Bypass $(If ($NoExit) {'-NoExit '})-Command ""&'$CommandPath'$($ArgumentList.GetEnumerator().ForEach({"" -$($_.Key):$(If ($_.Value -Is [Bool] -Or $_.Value -is [Switch]) {'$'})$($_.Value)""}) -join '')"""
		"Verb" = If ($Admin) {"RunAs"} Else {"Open"}
		"WindowStyle" = If ($Hidden) {"Hidden"} Else {"Normal"}
	}
	Start-Process @SapsArgs
}

Function Start-AsAdmin {
	Param(
		[Parameter(Position=0, Mandatory=$True)]
		[System.Management.Automation.FunctionInfo]$Func,
		
		[Parameter(Position=1)]
		[HashTable]$Arguments,
		
		[String]$TaskPath,
		[String]$TaskName,
		
		[String] $PipeName = ""
	)
	# Example usage: Start-AsAdmin $(Get-Command -Name Main) $PSBoundParameters -TaskPath "\" -TaskName "BackgroundTask"
	Enum PipeMode {
		Read
		Write
	}
	# This is about the most unique but consistent pipe name I could come up with
	If ($PipeName -eq "") {
		$PipeName = "$($MyInvocation.ScriptName)-$($Func.Name)"
	}
	# If the function being run writes character 0 twice on a line, it'll stop passing data across the pipe early
	$CtlEnd = "`0`0"
	
	$SchTaskParams = @{
		TaskName = [String]$TaskName
		TaskPath = [String]$TaskPath  # Coalesce to null string, let EA SilentlyContinue handle this case
		ErrorAction = "SilentlyContinue"
	}
	# Try to get a reference to the specified scheduled task
	$SchTask = Get-ScheduledTask @SchTaskParams
	
	# Get a "client" pipe in the output direction (why client serves data and server receives it, I have no idea)
	# It would make sense to switch them, but pipe server streams don't have a connect method with a timeout
	$Pipe = New-Object System.IO.Pipes.NamedPipeClientStream(".", $PipeName, [System.IO.Pipes.PipeDirection]::Out)
	# Time out the connection after 1 second (this should be plenty of time if the server is already waiting)
	Try {
		$Pipe.Connect(1)
		$Mode = [PipeMode]::Write
	} Catch [TimeoutException] {
		$Pipe.Dispose()
		$Mode = [PipeMode]::Read
	}
	If ($Mode -eq [PipeMode]::Write) {
		# If there's no scheduled task but there is a task name, create the scheduled task
		If (!$SchTask -and $TaskName) {
			$SchTaskSettings = New-ScheduledTaskSettingsSet -Priority 5 -AllowStartIfOnBatteries -Hidden
			$SchTaskSettings.UseUnifiedSchedulingEngine = $False
			$SchTaskPrincipal = New-ScheduledTaskPrincipal -Id Author -RunLevel Highest -UserId $([System.Environment]::UserName)
			$ArgStr = ""
			If ($Arguments) {
				$ArgStrB = [System.Text.StringBuilder]::New()
				$Arguments.GetEnumerator().ForEach({[void]$ArgStrB.Append(" -$($_.Key):$(If ($_.Value -Is [Bool] -Or $_.Value -is [Switch]) {'$'})$($_.Value)")})
				$ArgStr = $ArgStrB.ToString()
			}
			$SchTaskAction =  New-ScheduledTaskAction -Execute $(Get-Process -Id $PID).Path -WorkingDirectory $PWD -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -Command ""&'$($MyInvocation.ScriptName)'$ArgStr"""
			$SchTask = New-ScheduledTask -Action $SchTaskAction -Principal $SchTaskPrincipal -Settings $SchTaskSettings
			$SchTaskParams = @{
				InputObject = $SchTask
				TaskName = $TaskName
			}
			If ($TaskPath) {
				$SchTaskParams['TaskPath'] = $TaskPath
			}
			Register-ScheduledTask @SchTaskParams
		}

		$StreamWriter = New-Object System.IO.StreamWriter($Pipe)
		# Autoflush to preclude the need to flush after every write
		$StreamWriter.AutoFlush = $True
		# Lead with the control sequence just to get the pipe moving
		$StreamWriter.WriteLine($CtlEnd)
		# Save off the current output stream, in case it's not stdout
		$CurrentOut = [Console]::Out
		[Console]::SetOut($StreamWriter)
		# NOTE: If an error occurs in the function being executed or when cleaning up, this function will try to run again!
		# Depend on the function using Console.Write (or Write-Indirectable above) for output
		Try {
			& $Func @Arguments
		} Catch {}
		[Console]::SetOut($CurrentOut)
		$StreamWriter.WriteLine($CtlEnd)
		# Dispose to clean up
		$StreamWriter.Dispose()
		$Pipe.Dispose()
	} Else {

		# If there's no scheduled task, restart the current script as admin in the background
		If ($SchTask) {
			Start-ScheduledTask -InputObject $SchTask
		} Else {
			Restart-Script $MyInvocation.ScriptName $Arguments -Admin -Hidden
		}
		
		# Get a "server" pipe in the input direction and wait indefinitely for it to connect
		$Pipe = New-Object System.IO.Pipes.NamedPipeServerStream($PipeName, [System.IO.Pipes.PipeDirection]::In)
		$Pipe.WaitForConnection()
		
		$StreamReader = New-Object System.IO.StreamReader($Pipe)
		
		# Unfortunately, there's no way to time this out...
		# After the first line is read, though, everything flows quite quickly
		$Line = $StreamReader.ReadLine()
		# Output needs to start with the control sequence
		If ($Line -match "^$CtlEnd$") {
			$Line = ""
			While ($Line -notmatch "^$CtlEnd$") {
				If ($Line) {
					Write-Indirectable $Line
				}
				Start-Sleep -Milliseconds 5
				$Line = $StreamReader.ReadLine()
			}
		} Else {
			Write-Indirectable "Invalid data sent across pipe!"
		}
		
		# Dispose to clean up
		$StreamReader.Dispose()
		$Pipe.Dispose()
	}
}

# Window and mouse control stuff
Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing,System.Drawing.Primitives @"
	using System;
	using System.Drawing;
	using System.Runtime.InteropServices;
	using System.Windows.Forms;
	
	//https://msdn.microsoft.com/en-us/library/windows/desktop/ms646273(v=vs.85).aspx
	[StructLayout(LayoutKind.Sequential)]
	public struct MOUSEINPUT {
		public int    dx ;
		public int    dy ;
		public int    mouseData ;
		public int    dwFlags;
		public int    time;
		public IntPtr dwExtraInfo;
	}
	
	//https://msdn.microsoft.com/en-us/library/windows/desktop/ms646273(v=vs.85).aspx
	[StructLayout(LayoutKind.Sequential)]
	public struct KEYBDINPUT {
		public int    wVk ;
		public int    wScan ;
		public int    dwFlags;
		public int    time;
		public IntPtr dwExtraInfo;
	}
	
	[StructLayout(LayoutKind.Sequential)]
	public struct HARDWAREINPUT {
		public uint uMsg;
		public ushort wParamL;
		public ushort wParamH;
	}
	
	[StructLayout(LayoutKind.Explicit)]
	public struct INPUTUNION {
		[FieldOffset(0)] public MOUSEINPUT mi;
		[FieldOffset(0)] public KEYBDINPUT ki;
		[FieldOffset(0)] public HARDWAREINPUT hi;
	}
	
	//https://msdn.microsoft.com/en-us/library/windows/desktop/ms646270(v=vs.85).aspx
	[StructLayout(LayoutKind.Sequential)]
	public struct INPUT { 
		public int        type; // 0 = INPUT_MOUSE,
								// 1 = INPUT_KEYBOARD
								// 2 = INPUT_HARDWARE
		public INPUTUNION u;
	}

	public class Mouse {		
		//This covers most use cases although complex mice may have additional buttons
		//There are additional constants you can use for those cases, see the msdn page
		const int MOUSEEVENTF_MOVED      = 0x0001;
		const int MOUSEEVENTF_LEFTDOWN   = 0x0002;
		const int MOUSEEVENTF_LEFTUP     = 0x0004;
		const int MOUSEEVENTF_RIGHTDOWN  = 0x0008;
		const int MOUSEEVENTF_RIGHTUP    = 0x0010;
		const int MOUSEEVENTF_MIDDLEDOWN = 0x0020;
		const int MOUSEEVENTF_MIDDLEUP   = 0x0040;
		const int MOUSEEVENTF_WHEEL      = 0x0080;
		const int MOUSEEVENTF_XDOWN      = 0x0100;
		const int MOUSEEVENTF_XUP        = 0x0200;
		const int MOUSEEVENTF_ABSOLUTE   = 0x8000;

		//https://msdn.microsoft.com/en-us/library/windows/desktop/ms646310(v=vs.85).aspx
		[DllImport("user32.dll")]
		extern static uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
		
		public static void MoveMouseToPoint(int x, int y) {
			INPUT[] input = new INPUT[1];
			input[0].u.mi.dx = x * 65535 / System.Windows.Forms.Screen.PrimaryScreen.Bounds.Width;
			input[0].u.mi.dy = y * 0xFFFF / System.Windows.Forms.Screen.PrimaryScreen.Bounds.Height;
			input[0].u.mi.dwFlags = MOUSEEVENTF_MOVED | MOUSEEVENTF_ABSOLUTE;
			SendInput(1, input, Marshal.SizeOf(input[0]));
		}
		
		public static void LeftClick() {
			INPUT[] input = new INPUT[2];
			input[0].u.mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
			input[1].u.mi.dwFlags = MOUSEEVENTF_LEFTUP;
			SendInput(2, input, Marshal.SizeOf(input[0]));
		}

		public static void LeftClickAtPoint(int x, int y) {
			//Move the mouse
			INPUT[] input = new INPUT[3];
			input[0].u.mi.dx = x*(65535/System.Windows.Forms.Screen.PrimaryScreen.Bounds.Width);
			input[0].u.mi.dy = y*(65535/System.Windows.Forms.Screen.PrimaryScreen.Bounds.Height);
			input[0].u.mi.dwFlags = MOUSEEVENTF_MOVED | MOUSEEVENTF_ABSOLUTE;
			//Left mouse button down
			input[1].u.mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
			//Left mouse button up
			input[2].u.mi.dwFlags = MOUSEEVENTF_LEFTUP;
			SendInput(3, input, Marshal.SizeOf(input[0]));
		}
	}
	
	public class Keyboard {
		const int KEYEVENTF_EXTENDEDKEY = 0x0001;
		const int KEYEVENTF_KEYUP       = 0x0002;
		const int KEYEVENTF_UNICODE     = 0x0004;
		const int KEYEVENTF_SCANCODE    = 0x0008;
		
		const int VK_LBUTTON 				= 0x01; 	// Left mouse button
		const int VK_RBUTTON 				= 0x02; 	// Right mouse button
		const int VK_CANCEL 				= 0x03; 	// Control-break processing
		const int VK_MBUTTON 				= 0x04; 	// Middle mouse button (three-button mouse)
		const int VK_XBUTTON1 				= 0x05; 	// X1 mouse button
		const int VK_XBUTTON2 				= 0x06; 	// X2 mouse button
		const int VK_BACK 					= 0x08; 	// BACKSPACE key
		const int VK_TAB 					= 0x09; 	// TAB key
		const int VK_CLEAR 					= 0x0C; 	// CLEAR key
		const int VK_RETURN 				= 0x0D; 	// ENTER key
		const int VK_SHIFT 					= 0x10; 	// SHIFT key
		const int VK_CONTROL 				= 0x11; 	// CTRL key
		const int VK_MENU 					= 0x12; 	// ALT key
		const int VK_PAUSE 					= 0x13; 	// PAUSE key
		const int VK_CAPITAL 				= 0x14; 	// CAPS LOCK key
		const int VK_KANA 					= 0x15; 	// IME Kana mode
		const int VK_HANGUEL 				= 0x15; 	// IME Hanguel mode (maintained for compatibility; use VK_HANGUL)
		const int VK_HANGUL 				= 0x15; 	// IME Hangul mode
		const int VK_IME_ON 				= 0x16; 	// IME On
		const int VK_JUNJA 					= 0x17; 	// IME Junja mode
		const int VK_FINAL 					= 0x18; 	// IME final mode
		const int VK_HANJA 					= 0x19; 	// IME Hanja mode
		const int VK_KANJI 					= 0x19; 	// IME Kanji mode
		const int VK_IME_OFF 				= 0x1A; 	// IME Off
		const int VK_ESCAPE 				= 0x1B; 	// ESC key
		const int VK_CONVERT 				= 0x1C; 	// IME convert
		const int VK_NONCONVERT 			= 0x1D; 	// IME nonconvert
		const int VK_ACCEPT 				= 0x1E; 	// IME accept
		const int VK_MODECHANGE 			= 0x1F; 	// IME mode change request
		const int VK_SPACE 					= 0x20; 	// SPACEBAR
		const int VK_PRIOR 					= 0x21; 	// PAGE UP key
		const int VK_NEXT 					= 0x22; 	// PAGE DOWN key
		const int VK_END 					= 0x23; 	// END key
		const int VK_HOME 					= 0x24; 	// HOME key
		const int VK_LEFT 					= 0x25; 	// LEFT ARROW key
		const int VK_UP 					= 0x26; 	// UP ARROW key
		const int VK_RIGHT 					= 0x27; 	// RIGHT ARROW key
		const int VK_DOWN 					= 0x28; 	// DOWN ARROW key
		const int VK_SELECT 				= 0x29; 	// SELECT key
		const int VK_PRINT 					= 0x2A; 	// PRINT key
		const int VK_EXECUTE 				= 0x2B; 	// EXECUTE key
		const int VK_SNAPSHOT 				= 0x2C; 	// PRINT SCREEN key
		const int VK_INSERT 				= 0x2D; 	// INS key
		const int VK_DELETE 				= 0x2E; 	// DEL key
		const int VK_HELP 					= 0x2F; 	// HELP key
		const int VK_0 						= 0x30; 	// 0 key
		const int VK_1 						= 0x31; 	// 1 key
		const int VK_2 						= 0x32; 	// 2 key
		const int VK_3 						= 0x33; 	// 3 key
		const int VK_4 						= 0x34; 	// 4 key
		const int VK_5 						= 0x35; 	// 5 key
		const int VK_6 						= 0x36; 	// 6 key
		const int VK_7 						= 0x37; 	// 7 key
		const int VK_8 						= 0x38; 	// 8 key
		const int VK_9 						= 0x39; 	// 9 key
		const int VK_A 						= 0x41; 	// A key
		const int VK_B 						= 0x42; 	// B key
		const int VK_C 						= 0x43; 	// C key
		const int VK_D 						= 0x44; 	// D key
		const int VK_E 						= 0x45; 	// E key
		const int VK_F 						= 0x46; 	// F key
		const int VK_G 						= 0x47; 	// G key
		const int VK_H 						= 0x48; 	// H key
		const int VK_I 						= 0x49; 	// I key
		const int VK_J 						= 0x4A; 	// J key
		const int VK_K 						= 0x4B; 	// K key
		const int VK_L 						= 0x4C; 	// L key
		const int VK_M 						= 0x4D; 	// M key
		const int VK_N 						= 0x4E; 	// N key
		const int VK_O 						= 0x4F; 	// O key
		const int VK_P 						= 0x50; 	// P key
		const int VK_Q 						= 0x51; 	// Q key
		const int VK_R 						= 0x52; 	// R key
		const int VK_S 						= 0x53; 	// S key
		const int VK_T 						= 0x54; 	// T key
		const int VK_U 						= 0x55; 	// U key
		const int VK_V 						= 0x56; 	// V key
		const int VK_W 						= 0x57; 	// W key
		const int VK_X 						= 0x58; 	// X key
		const int VK_Y 						= 0x59; 	// Y key
		const int VK_Z 						= 0x5A; 	// Z key
		const int VK_LWIN 					= 0x5B; 	// Left Windows key (Natural keyboard)
		const int VK_RWIN 					= 0x5C; 	// Right Windows key (Natural keyboard)
		const int VK_APPS 					= 0x5D; 	// Applications key (Natural keyboard)
		const int VK_SLEEP 					= 0x5F; 	// Computer Sleep key
		const int VK_NUMPAD0 				= 0x60; 	// Numeric keypad 0 key
		const int VK_NUMPAD1 				= 0x61; 	// Numeric keypad 1 key
		const int VK_NUMPAD2 				= 0x62; 	// Numeric keypad 2 key
		const int VK_NUMPAD3 				= 0x63; 	// Numeric keypad 3 key
		const int VK_NUMPAD4 				= 0x64; 	// Numeric keypad 4 key
		const int VK_NUMPAD5 				= 0x65; 	// Numeric keypad 5 key
		const int VK_NUMPAD6 				= 0x66; 	// Numeric keypad 6 key
		const int VK_NUMPAD7 				= 0x67; 	// Numeric keypad 7 key
		const int VK_NUMPAD8 				= 0x68; 	// Numeric keypad 8 key
		const int VK_NUMPAD9 				= 0x69; 	// Numeric keypad 9 key
		const int VK_MULTIPLY 				= 0x6A; 	// Multiply key
		const int VK_ADD 					= 0x6B; 	// Add key
		const int VK_SEPARATOR 				= 0x6C; 	// Separator key
		const int VK_SUBTRACT 				= 0x6D; 	// Subtract key
		const int VK_DECIMAL 				= 0x6E; 	// Decimal key
		const int VK_DIVIDE 				= 0x6F; 	// Divide key
		const int VK_F1 					= 0x70; 	// F1 key
		const int VK_F2 					= 0x71; 	// F2 key
		const int VK_F3 					= 0x72; 	// F3 key
		const int VK_F4 					= 0x73; 	// F4 key
		const int VK_F5 					= 0x74; 	// F5 key
		const int VK_F6 					= 0x75; 	// F6 key
		const int VK_F7 					= 0x76; 	// F7 key
		const int VK_F8 					= 0x77; 	// F8 key
		const int VK_F9 					= 0x78; 	// F9 key
		const int VK_F10 					= 0x79; 	// F10 key
		const int VK_F11 					= 0x7A; 	// F11 key
		const int VK_F12 					= 0x7B; 	// F12 key
		const int VK_F13 					= 0x7C; 	// F13 key
		const int VK_F14 					= 0x7D; 	// F14 key
		const int VK_F15 					= 0x7E; 	// F15 key
		const int VK_F16 					= 0x7F; 	// F16 key
		const int VK_F17 					= 0x80; 	// F17 key
		const int VK_F18 					= 0x81; 	// F18 key
		const int VK_F19 					= 0x82; 	// F19 key
		const int VK_F20 					= 0x83; 	// F20 key
		const int VK_F21 					= 0x84; 	// F21 key
		const int VK_F22 					= 0x85; 	// F22 key
		const int VK_F23 					= 0x86; 	// F23 key
		const int VK_F24 					= 0x87; 	// F24 key
		const int VK_NUMLOCK 				= 0x90; 	// NUM LOCK key
		const int VK_SCROLL 				= 0x91; 	// SCROLL LOCK key
		const int VK_LSHIFT 				= 0xA0; 	// Left SHIFT key
		const int VK_RSHIFT 				= 0xA1; 	// Right SHIFT key
		const int VK_LCONTROL 				= 0xA2; 	// Left CONTROL key
		const int VK_RCONTROL 				= 0xA3; 	// Right CONTROL key
		const int VK_LMENU 					= 0xA4; 	// Left ALT key
		const int VK_RMENU 					= 0xA5; 	// Right ALT key
		const int VK_BROWSER_BACK 			= 0xA6; 	// Browser Back key
		const int VK_BROWSER_FORWARD 		= 0xA7; 	// Browser Forward key
		const int VK_BROWSER_REFRESH 		= 0xA8; 	// Browser Refresh key
		const int VK_BROWSER_STOP 			= 0xA9; 	// Browser Stop key
		const int VK_BROWSER_SEARCH 		= 0xAA; 	// Browser Search key
		const int VK_BROWSER_FAVORITES 		= 0xAB; 	// Browser Favorites key
		const int VK_BROWSER_HOME 			= 0xAC; 	// Browser Start and Home key
		const int VK_VOLUME_MUTE 			= 0xAD; 	// Volume Mute key
		const int VK_VOLUME_DOWN 			= 0xAE; 	// Volume Down key
		const int VK_VOLUME_UP 				= 0xAF; 	// Volume Up key
		const int VK_MEDIA_NEXT_TRACK 		= 0xB0; 	// Next Track key
		const int VK_MEDIA_PREV_TRACK 		= 0xB1; 	// Previous Track key
		const int VK_MEDIA_STOP 			= 0xB2; 	// Stop Media key
		const int VK_MEDIA_PLAY_PAUSE 		= 0xB3; 	// Play/Pause Media key
		const int VK_LAUNCH_MAIL 			= 0xB4; 	// Start Mail key
		const int VK_LAUNCH_MEDIA_SELECT 	= 0xB5; 	// Select Media key
		const int VK_LAUNCH_APP1 			= 0xB6; 	// Start Application 1 key
		const int VK_LAUNCH_APP2 			= 0xB7; 	// Start Application 2 key
		const int VK_OEM_1 					= 0xBA; 	// Used for miscellaneous characters; it can vary by keyboard. For the US standard keyboard, the ';:' key
		const int VK_OEM_PLUS 				= 0xBB; 	// For any country/region, the '+' key
		const int VK_OEM_COMMA 				= 0xBC; 	// For any country/region, the ',' key
		const int VK_OEM_MINUS 				= 0xBD; 	// For any country/region, the '-' key
		const int VK_OEM_PERIOD 			= 0xBE; 	// For any country/region, the '.' key
		const int VK_OEM_2 					= 0xBF; 	// Used for miscellaneous characters; it can vary by keyboard. For the US standard keyboard, the '/?' key
		const int VK_OEM_3 					= 0xC0; 	// Used for miscellaneous characters; it can vary by keyboard. For the US standard keyboard, the '`~' key
		const int VK_OEM_4 					= 0xDB; 	// Used for miscellaneous characters; it can vary by keyboard. For the US standard keyboard, the '[{' key
		const int VK_OEM_5 					= 0xDC; 	// Used for miscellaneous characters; it can vary by keyboard. For the US standard keyboard, the '\|' key
		const int VK_OEM_6 					= 0xDD; 	// Used for miscellaneous characters; it can vary by keyboard. For the US standard keyboard, the ']}' key
		const int VK_OEM_7 					= 0xDE; 	// Used for miscellaneous characters; it can vary by keyboard. For the US standard keyboard, the 'single-quote/double-quote' key
		const int VK_OEM_8 					= 0xDF; 	// Used for miscellaneous characters; it can vary by keyboard.
		const int VK_OEM_102 				= 0xE2; 	// The <> keys on the US standard keyboard, or the \\| key on the non-US 102-key keyboard
		const int VK_PROCESSKEY 			= 0xE5; 	// IME PROCESS key
		const int VK_PACKET 				= 0xE7; 	// Used to pass Unicode characters as if they were keystrokes. The VK_PACKET key is the low word of a 32-bit Virtual Key value used for non-keyboard input methods. For more information, see Remark in KEYBDINPUT, SendInput, WM_KEYDOWN, and WM_KEYUP
		const int VK_ATTN 					= 0xF6; 	// Attn key
		const int VK_CRSEL 					= 0xF7; 	// CrSel key
		const int VK_EXSEL 					= 0xF8; 	// ExSel key
		const int VK_EREOF 					= 0xF9; 	// Erase EOF key
		const int VK_PLAY 					= 0xFA; 	// Play key
		const int VK_ZOOM 					= 0xFB; 	// Zoom key
		const int VK_NONAME 				= 0xFC; 	// Reserved
		const int VK_PA1 					= 0xFD; 	// PA1 key
		const int VK_OEM_CLEAR 				= 0xFE; 	// Clear key	
		
		//https://msdn.microsoft.com/en-us/library/windows/desktop/ms646310(v=vs.85).aspx
		[DllImport("user32.dll")]
		extern static uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
		
		public static uint SendVirtualKey(int keyCode) {
			INPUT[] input = new INPUT[2];
			input[0].type = 1;
			input[0].u.ki.wVk = keyCode;
			input[1].type = 1;
			input[1].u.ki.wVk = keyCode;
			input[1].u.ki.dwFlags = KEYEVENTF_KEYUP;
			return SendInput(2, input, Marshal.SizeOf(input[0]));
		}
		
		public static uint SendUnicode(int keyCode) {
			INPUT[] input = new INPUT[2];
			input[0].type = 1;
			input[0].u.ki.wScan = keyCode;
			input[0].u.ki.dwFlags = KEYEVENTF_UNICODE;
			input[1].type = 1;
			input[1].u.ki.wScan = keyCode;
			input[1].u.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
			return SendInput(2, input, Marshal.SizeOf(input[0]));
		}
	}
	
	public struct RECT {
		public int Left;        // x position of upper-left corner
		public int Top;         // y position of upper-left corner
		public int Right;       // x position of lower-right corner
		public int Bottom;      // y position of lower-right corner
	}

    public class Window {
		const int SW_HIDE				= 0;
		const int SW_SHOWNORMAL			= 1;
		const int SW_NORMAL				= 1;
		const int SW_SHOWMINIMIZED		= 2;
		const int SW_SHOWMAXIMIZED		= 3;
		const int SW_MAXIMIZE			= 3;
		const int SW_SHOWNOACTIVATE		= 4;
		const int SW_SHOW				= 5;
		const int SW_MINIMIZE			= 6;
		const int SW_SHOWMINNOACTIVE	= 7;
		const int SW_SHOWNA				= 8;
		const int SW_RESTORE			= 9;
		const int SW_SHOWDEFAULT		= 10;
		const int SW_FORCEMINIMIZE		= 11;
	
		[DllImport("user32.dll")]
		[return: MarshalAs(UnmanagedType.Bool)]
		public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
		
		[DllImport("user32.dll")]
		[return: MarshalAs(UnmanagedType.Bool)]
		public static extern bool SetForegroundWindow(IntPtr hWnd);

		[DllImport("user32.dll")]
		[return: MarshalAs(UnmanagedType.Bool)]
		public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
		
		public static void ActivateWindow(IntPtr hWnd) {
			SetForegroundWindow(hWnd);
			ShowWindow(hWnd, SW_SHOW);
		}
		
		public static RECT GetWindowCoords(IntPtr hWnd) {
			RECT outp;
			GetWindowRect(hWnd, out outp);
			return outp;
		}
    }
"@
