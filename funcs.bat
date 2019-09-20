@echo off
setlocal enabledelayedexpansion
::goto :demo
echo/Script is disabled.  Un-comment the previous line to enable script.
timeout /t 30
goto :eof

:demo
if "%*" equ "" (
	echo/No date specified^!  Defaulting to the day before yesterday.
	echo/
) else (
	for /f "tokens=1,2,3 delims=/ " %%a in ('echo/%*') do (
		if "%%c" equ "" (
			echo/Invalid date specified^!  Defaulting to the day before yesterday.
			echo/
		)
	)
)
echo/
call :gettime _tim
set _sec=%_tim:~0,-3%.%_tim:~-3%
echo/Current time (milliseconds): %_tim%
echo/Current time (seconds)     : %_sec%
echo/
set "_varwithzeros=0009"
echo/Before: %_varwithzeros%
call :remzeros _var %_varwithzeros%
call :remzeros _varwithzeros
echo/After : %_varwithzeros%
echo/
set "_strwithspaces=    string"
echo/Before: %_strwithspaces%
call :remspaces _str %_strwithspaces%
call :remspaces _strwithspaces
echo/After : %_strwithspaces%
echo/
set "_reversestr=esrever"
call :strlen _lenofstr %_reversestr%
echo/Before: %_reversestr% (%_lenofstr% characters)
call :strrev _str %_reversestr%
call :strrev _reversestr
echo/After : %_reversestr% (%_lenofstr% characters)
echo/
set "_strwithdups=Thiiiiiis iiis a striiiiiiiiiiiiiiing"
echo/Before: %_strwithdups%
call :remdupchars _str "i" %_strwithdups%
call :remdupchars _strwithdups i
echo/After : %_strwithdups%
echo/
call :getcurdate _curdate
call :getcurdate _curday _curmonth _curyear
call :monthtrans _monthstr %_curmonth%
echo/Current date: %_curday% %_monthstr:~0,3%, %_curyear%
call :dj _dj %_curday% %_curmonth% %_curyear%
call :dj _curdj %_curdate%
echo/Julian date : %_curdj%
echo/
set "_date=%*"
for /f "tokens=1,2,3 delims=/ " %%a in ('echo/%_date%') do (
	set _pastday=%%a
	set _pastmonth=%%b
	set _pastyear=%%c
)
if "%_pastyear%" equ "" (
	set /a _dj=_curdj-2
	call :date _pastday _pastmonth _pastyear !_dj!
) else (
	call :dj _dj %_date%
)
call :datediff _dif %_curday% %_curmonth% %_curyear% %_pastday% %_pastmonth% %_pastyear%
call :monthtrans _monthstr %_pastmonth%
echo/Date provided: %_pastday% %_monthstr%, %_pastyear%
echo/Julian date  : %_dj%
echo/This date is %_dif% days in the past
echo/
goto :eof

:gettime <return_var>
::Get the current time in milliseconds
::Requires the remzeros subroutine
setlocal enabledelayedexpansion
for /f "tokens=1-4 delims=-" %%a in ('powershell -command "get-date" -format "h-m-s-fff"') do (
	set _hh=%%a
	set _mm=%%b
	set _ss=%%c
	set _ssss=%%d
)
call :remzeros _ssss
endlocal & set /a "%~1=%_hh%*3600000+%-mm%*60000+%-ss%*1000+%_ssss%"
exit /b 0

:remzeros <return_var> [<value>]
::Remove leading 0s
::Removes all spaces as well - intended use is for numbers only
::Read the value from the provided variable if no value is given
setlocal enabledelayedexpansion
if "%~2" equ "" (
	set "_val=!%~1!"
	set "_val=!_val: =!"
) else (
	set "_val=%~2"
)
:remzero
if "%_val:~1%" neq "" (
	if "%_val:~0,1%" equ "0" (
		set "_val=%_val:~1%"
		goto :remzero
	)
)
endlocal & set /a "%~1=%_val%"
exit /b 0

:remspaces <return_var> [<string>]
::Remove leading spaces
::Read the string from the provided variable if no string is given
setlocal enabledelayedexpansion
if "%~2" equ "" (
	set "_val=!%~1!"
) else (
	set "_val=%~2"
)
:remspace
if "%_val:~0,1%" equ " " (
	set "_val=%_val:~1%"
	goto :remspace
)
endlocal & set "%~1=%_val%"
exit /b 0

:strrev <return_var> [<string>]
::Reverse a string
::Read the string from the provided variable if no string is given
::Requires the strlen subroutine
setlocal enabledelayedexpansion
if "%~2" equ "" (
	set "_str=!%~1!"
) else (
	set "_str=%~2"
)
if "%_str%" equ "" (
	set "%~1="
	exit /b 0
)
set "_ret="
call :strlen _len "%_str%"
if %_len% equ 0 (
	endlocal & set "%~1=%_ret%"
	exit /b 0
)
set /a _len-=1
for /l %%a in (0,1,%_len%) do (
	set "_ret=!_str:~0,1!!_ret!"
	set "_str=!_str:~1!"
)
endlocal & set "%~1=%_ret%"
exit /b 0

:strlen <return_var> <string>
::Calculate the length of a string
::Read the string from the provided variable if no string is given
setlocal enabledelayedexpansion
if "%~2" equ "" (
	set _ret=0
) else (
	set _ret=1
)
set "_str=%~2"
for %%a in (4096 2048 1024 512 256 128 64 32 16 8 4 2 1) do (
	if "!_str:~%%a,1!" neq "" (
		set /a _ret+=%%a
		set "_str=!_str:~%%a!"
	)
)
endlocal & set "%~1=%_ret%"
exit /b 0

:remdupchars <return_var> <character> [<string>]
::Remove duplicates of a specified character from a string
::Read the string from the provided variable if no string is given
setlocal enabledelayedexpansion
if "%~3" equ "" (
	set "_str=!%~1!"
) else (
	set "_str=%~3"
)
set "_char=%~2"
set "_char=%_char:~0,1%"
:remdupchar
set "_tmpstr=!_str:%_char%%_char%=%_char%!"
if "%_tmpstr%" neq "%_str%" (
	set "_str=%_tmpstr%"
	goto :remdupchar
)
endlocal & set "%~1=%_str%"
exit /b 0

:getcurdate <return_var> or <day_var> <month_var> <year var>
::Get today's date
::This requires modifications to the registry in order to force the date format required
::Registry changes are reverted once no longer needed
setlocal enabledelayedexpansion
for /f "tokens=1-3 delims=/" %%a in ('powershell -command "get-date" -format "dd/MM/yyyy"') do (
	set _dd=%%a
	set _mm=%%b
	set _yy=%%c
)
endlocal & if "%~3" equ "" (
	set "%~1=%_dd%/%_mm%/%_yy%"
) else (
	set "%~1=%_dd%"
	set "%~2=%_mm%"
	set "%~3=%_yy%"
)
exit /b 0

:dj <return_var> <day> <month> <year>
::Calculate a julian date given a day, month, and year
::Default to the current date if no date is given
::Requires the remzeros subroutine
setlocal enabledelayedexpansion
set _date="%*"
set _date=%_date:"=%
set _var="%1"
set _var=%_var:"=%
set "_date=!_date:%_var% =!"
for /f "tokens=1-3 delims=/ " %%a in ('echo/%_date%') do (
	call :remzeros _day %%a
	call :remzeros _month %%b
	call :remzeros _year %%c
)
if %_month% lss 3 set /a _month+=12,_year-=1
set /a _a=_year/100
set /a _b=_a/4
set /a _c=2-_a+_b
set /a _e=36525*(_year+4716)/100
set /a _f=306001*(_month+1)/10000
set /a _dj=_c+_day+_e+_f-1524
endlocal & set /a "%~1=%_dj%"
exit /b 0

:date <return_day_var> <return_month_var> <return_year_var> <dj>
::Calculate the day, month, and year given a julian date
setlocal enabledelayedexpansion
set /a _dj=%4
set /a _w=(_dj*100-186721625)/3652425
set /a _x=_w/4
set /a _a=_dj+1+_w-_x
set /a _b=_a+1524
set /a _c=(_b*100-12210)/36525
set /a _d=36525*_c/100
set /a _e=(_b-_d)*10000/306001
set /a _f=306001*_e/10000
set /a _day=_b-_d-_f
set /a _month=_e-1
set /a _year=_c-4716
if %_month% gtr 12 set /a _month-=12
if %_month% lss 3 set /a _year+=1
endlocal & set "%~1=%_day%" & set "%~2=%_month%" & set "%~3=%_year%"
exit /b 0

:datediff <return_var> <day 1> <month 1> <year 1> <day 2> <month 2> <year 2>
::Calculate the difference between two dates
::Requires the remzeros and the dj subroutines
setlocal enabledelayedexpansion
set "_var=%~1"
set "_args=%*"
set "_args=!_args:%_var% =!"
set "_args=%_args:"=%"
for /f "tokens=1-6 delims=/ " %%a in ('echo/%_args%') do (
	call :remzeros _day1 %%a
	call :remzeros _month1 %%b
	call :remzeros _year1 %%c
	call :remzeros _day2 %%d
	call :remzeros _month2 %%e
	call :remzeros _year2 %%f
)
call :dj _dj1 %_day1% %_month1% %_year1%
call :dj _dj2 %_day2% %_month2% %_year2%
set /a _diff=_dj1-_dj2
endlocal & set /a "%~1=%_diff%"
exit /b 0

:monthtrans <return_var> <month>
::Translate a numeric month into the name of the month
setlocal enabledelayedexpansion
call :remzeros _month %~2
if %_month% equ 1 set "_name=January"
if %_month% equ 2 set "_name=February"
if %_month% equ 3 set "_name=March"
if %_month% equ 4 set "_name=April"
if %_month% equ 5 set "_name=May"
if %_month% equ 6 set "_name=June"
if %_month% equ 7 set "_name=July"
if %_month% equ 8 set "_name=August"
if %_month% equ 9 set "_name=September"
if %_month% equ 10 set "_name=October"
if %_month% equ 11 set "_name=November"
if %_month% equ 12 set "_name=December"
endlocal & set "%~1=%_name%"
exit /b 0
