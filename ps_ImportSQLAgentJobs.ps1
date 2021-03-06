#Clear screen (for testing)
Clear-Host

#Define target repository
$DBServer = "RPRMBSDEVDB81.REALPOINTDEV.GMACCM.COM"
$DBName = "dba_rep"
$UtilUser = "rp_util_reader"
#$UtilPwd = read-host "Password for" $UtilUser
$UtilPwd = get-content "C:\Users\nateh\Projects\dba-repository\ImportUserPwd.txt"

#SQLCMD timeout parameter
$QueryTimeout = 120

#Get list of servers to import data from
$sql_serverlist="
SELECT	sl.HostName
		,sl.ServerName + '.' + sl.Domain
FROM	dbo.ServerList sl
WHERE	sl.Import = 1
AND		sl.Active = 1
GROUP BY sl.HostName
		,sl.ServerName + '.' + sl.Domain;
"

#To Do If Invoke-SqlCmd Is Not Recognized in Windows PowerShell
#Add-PSSnapin SqlServerCmdletSnapin100
#Add-PSSnapin SqlServerProviderSnapin100

$servers = Invoke-Sqlcmd -ServerInstance $DBServer -Database $DBName -Query $sql_serverlist
#$servers | select-object

#Setup DataTable
$dt = new-object Data.DataTable
$col1 = new-object Data.DataColumn ServerName,([string])
$col2 = new-object Data.DataColumn JobName,([string])
$col3 = new-object Data.DataColumn JobSteps,([int])
$col4 = new-object Data.DataColumn Enabled,([int])
$col5 = new-object Data.DataColumn Schedule,([string])
$col6 = new-object Data.DataColumn OnFailureNotify,([string])
$col7 = new-object Data.DataColumn Description,([string])
$col8 = new-object Data.DataColumn OutputFile,([string])
$dt.columns.add($col1)
$dt.columns.add($col2)
$dt.columns.add($col3)
$dt.columns.add($col4)
$dt.columns.add($col5)
$dt.columns.add($col6)
$dt.columns.add($col7)
$dt.columns.add($col8)

#Loop through servers and pull in bak file data
foreach($server in $servers)
{
  #Retrieve ServerName from array
  $hostname = $server[0]
  $servername = $server[1]

  #Build SQL to retrieve records for import
  $sql_jobdata="
  SELECT  '$hostname' AS ServerName
		, [JobName] = msdb.dbo.sysjobs.name
		, [JobSteps] = stepcount
		, [Enabled] = msdb.dbo.sysjobs.[enabled]
		, [Schedule] = NULLIF(
			CASE WHEN msdb.dbo.sysjobs.[enabled] = 0
					THEN 'Disabled'
				WHEN msdb.dbo.sysjobs.job_id IS NULL
					THEN 'Unscheduled'
				WHEN msdb.dbo.sysschedules.freq_type = 0x1 -- OneTime
					THEN 'Once on ' + CONVERT(CHAR(10), CAST(CAST(msdb.dbo.sysschedules.active_start_date AS VARCHAR)AS DATETIME), 101)
				WHEN msdb.dbo.sysschedules.freq_type = 0x4 -- Daily
					THEN 'Daily'
				WHEN msdb.dbo.sysschedules.freq_type = 0x8 -- weekly
					THEN CASE WHEN msdb.dbo.sysschedules.freq_recurrence_factor = 1
								THEN 'Wkly on '
							WHEN msdb.dbo.sysschedules.freq_recurrence_factor > 1
								THEN 'Every ' + CAST(msdb.dbo.sysschedules.freq_recurrence_factor AS VARCHAR) + ' wks on '
						END
						+ LEFT(
							CASE WHEN msdb.dbo.sysschedules.freq_interval &  1 =  1 THEN 'Su, ' ELSE '' END
							+ CASE WHEN msdb.dbo.sysschedules.freq_interval &  2 =  2 THEN 'M, ' ELSE '' END
							+ CASE WHEN msdb.dbo.sysschedules.freq_interval &  4 =  4 THEN 'Tu, ' ELSE '' END
							+ CASE WHEN msdb.dbo.sysschedules.freq_interval &  8 =  8 THEN 'W, ' ELSE '' END
							+ CASE WHEN msdb.dbo.sysschedules.freq_interval & 16 = 16 THEN 'Th, ' ELSE '' END
							+ CASE WHEN msdb.dbo.sysschedules.freq_interval & 32 = 32 THEN 'F, ' ELSE '' END
							+ CASE WHEN msdb.dbo.sysschedules.freq_interval & 64 = 64 THEN 'Sa, ' ELSE '' END
							, LEN(
								CASE WHEN msdb.dbo.sysschedules.freq_interval &  1 =  1 THEN 'Su, ' ELSE '' END
								+ CASE WHEN msdb.dbo.sysschedules.freq_interval &  2 =  2 THEN 'M, ' ELSE '' END
								+ CASE WHEN msdb.dbo.sysschedules.freq_interval &  4 =  4 THEN 'Tu, ' ELSE '' END
								+ CASE WHEN msdb.dbo.sysschedules.freq_interval &  8 =  8 THEN 'W, ' ELSE '' END
								+ CASE WHEN msdb.dbo.sysschedules.freq_interval & 16 = 16 THEN 'Th, ' ELSE '' END
								+ CASE WHEN msdb.dbo.sysschedules.freq_interval & 32 = 32 THEN 'F, ' ELSE '' END
								+ CASE WHEN msdb.dbo.sysschedules.freq_interval & 64 = 64 THEN 'Sa, ' ELSE '' END
							)  - 1  -- LEN() ignores trailing spaces
						)
				WHEN msdb.dbo.sysschedules.freq_type = 0x10 -- monthly
					THEN CASE WHEN msdb.dbo.sysschedules.freq_recurrence_factor = 1
									THEN 'Mthly on the '
								WHEN msdb.dbo.sysschedules.freq_recurrence_factor > 1
								   THEN 'Every ' + CAST(msdb.dbo.sysschedules.freq_recurrence_factor AS VARCHAR) + ' mo on the '
							END
						+ CAST(msdb.dbo.sysschedules.freq_interval AS VARCHAR)
						+ CASE WHEN msdb.dbo.sysschedules.freq_interval IN (1, 21, 31)
									THEN 'st'
								WHEN msdb.dbo.sysschedules.freq_interval IN (2, 22)
									THEN 'nd'
								WHEN msdb.dbo.sysschedules.freq_interval IN (3, 23)
									THEN 'rd'
								ELSE 'th'
							END
				WHEN msdb.dbo.sysschedules.freq_type = 0x20 -- monthly relative
						THEN CASE WHEN msdb.dbo.sysschedules.freq_recurrence_factor = 1
										THEN 'Mthly on the '
									WHEN msdb.dbo.sysschedules.freq_recurrence_factor > 1
										THEN 'Every '+ CAST( msdb.dbo.sysschedules.freq_recurrence_factor AS VARCHAR )+ ' mths on the '
								END
						+ CASE msdb.dbo.sysschedules.freq_relative_interval
								WHEN 0x01 THEN 'first '
								WHEN 0x02 THEN 'second '
								WHEN 0x04 THEN 'third '
								WHEN 0x08 THEN 'fourth '
								WHEN 0x10 THEN 'last '
							END
						+ CASE msdb.dbo.sysschedules.freq_interval
								WHEN  1 THEN 'Su'
								WHEN  2 THEN 'M'
								WHEN  3 THEN 'Tu'
								WHEN  4 THEN 'W'
								WHEN  5 THEN 'Th'
								WHEN  6 THEN 'F'
								WHEN  7 THEN 'Sa'
								WHEN  8 THEN 'day'
								WHEN  9 THEN 'wk day'
								WHEN 10 THEN 'wknd day'
							END
				WHEN msdb.dbo.sysschedules.freq_type = 0x40
				   THEN 'Auto start when SQLServerAgent starts'
				WHEN msdb.dbo.sysschedules.freq_type = 0x80
				   THEN 'Starts whenever CPUs become idle'
				ELSE ''
			END
		+ CASE WHEN msdb.dbo.sysjobs.[enabled] = 0
					THEN ''
				WHEN msdb.dbo.sysjobs.job_id IS NULL
					THEN ''
				WHEN msdb.dbo.sysschedules.freq_subday_type = 0x1
				OR msdb.dbo.sysschedules.freq_type = 0x1
					THEN ' at '
						+ CASE -- Depends on time being integer to drop right-side digits
							WHEN(msdb.dbo.sysschedules.active_start_time % 1000000)/10000 = 0
								THEN '12'
									+ ':'  
									+ REPLICATE('0',2 - LEN(CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100)))
									+ CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100) 
									+ ' AM'
							WHEN (msdb.dbo.sysschedules.active_start_time % 1000000)/10000< 10
								THEN CONVERT(CHAR(1),(msdb.dbo.sysschedules.active_start_time % 1000000)/10000) 
									+ ':'  
									+ REPLICATE('0',2 - LEN(CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100))) 
									+ CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100) 
									+ ' AM'
							WHEN (msdb.dbo.sysschedules.active_start_time % 1000000)/10000 < 12
								THEN CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_start_time % 1000000)/10000) 
									+ ':'  
									+ REPLICATE('0',2 - LEN(CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100))) 
									+ CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100) 
									+ ' AM'
							WHEN (msdb.dbo.sysschedules.active_start_time % 1000000)/10000< 22
								THEN CONVERT(CHAR(1),((msdb.dbo.sysschedules.active_start_time % 1000000)/10000) - 12) 
									+ ':'  
									+ REPLICATE('0',2 - LEN(CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100))) 
									+ CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100) 
									+ ' PM'
							ELSE CONVERT(CHAR(2),((msdb.dbo.sysschedules.active_start_time % 1000000)/10000) - 12)
								+ ':'  
								+ REPLICATE('0',2 - LEN(CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100))) 
								+ CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100) 
								+ ' PM'
						END
				WHEN msdb.dbo.sysschedules.freq_subday_type IN (0x2, 0x4, 0x8)
					THEN ' every '
						+ CAST(msdb.dbo.sysschedules.freq_subday_interval AS VARCHAR)
						+ CASE freq_subday_type
							WHEN 0x2
								THEN ' sec'
							WHEN 0x4
								THEN ' min'
							WHEN 0x8
								THEN ' hr'
						END
					+ CASE
						WHEN msdb.dbo.sysschedules.freq_subday_interval > 1
							THEN 's'
						ELSE '' -- Added default 3/21/08; John Arnott
					END
				ELSE ''
		END
		+ CASE WHEN msdb.dbo.sysjobs.[enabled] = 0
					THEN ''
				WHEN msdb.dbo.sysjobs.job_id IS NULL
					THEN ''
				WHEN msdb.dbo.sysschedules.freq_subday_type IN (0x2, 0x4, 0x8)
					THEN ' btw '
						+ CASE -- Depends on time being integer to drop right-side digits
							WHEN(msdb.dbo.sysschedules.active_start_time % 1000000)/10000 = 0
								THEN '12'
								+ ':'  
								+ REPLICATE('0',2 - LEN(CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100)))
								+ RTRIM(CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100))
								+ ' AM'
							WHEN (msdb.dbo.sysschedules.active_start_time % 1000000)/10000< 10
								THEN CONVERT(CHAR(1),(msdb.dbo.sysschedules.active_start_time % 1000000)/10000) 
									+ ':'  
									+ REPLICATE('0',2 - LEN(CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100))) 
									+ RTRIM(CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100))
									+ ' AM'
							WHEN (msdb.dbo.sysschedules.active_start_time % 1000000)/10000 < 12
								THEN CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_start_time % 1000000)/10000) 
									+ ':'  
									+ REPLICATE('0',2 - LEN(CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100))) 
									+ RTRIM(CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100)) 
									+ ' AM'
							WHEN (msdb.dbo.sysschedules.active_start_time % 1000000)/10000< 22
								THEN CONVERT(CHAR(1),((msdb.dbo.sysschedules.active_start_time % 1000000)/10000) - 12) 
									+ ':'  
									+ REPLICATE('0',2 - LEN(CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100))) 
									+ RTRIM(CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100)) 
									+ ' PM'
							ELSE CONVERT(CHAR(2),((msdb.dbo.sysschedules.active_start_time % 1000000)/10000) - 12)
								+ ':'  
								+ REPLICATE('0',2 - LEN(CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100))) 
								+ RTRIM(CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_start_time % 10000)/100))
								+ ' PM'
						END
						+ ' and '
						+ CASE -- Depends on time being integer to drop right-side digits
							WHEN (msdb.dbo.sysschedules.active_end_time % 1000000)/10000 = 0
								THEN '12'
									+ ':'  
									+ REPLICATE('0',2 - LEN(CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_end_time % 10000)/100)))
									+ RTRIM(CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_end_time % 10000)/100))
									+ ' AM'
							WHEN (msdb.dbo.sysschedules.active_end_time % 1000000)/10000< 10
								THEN CONVERT(CHAR(1),(msdb.dbo.sysschedules.active_end_time % 1000000)/10000) 
								+ ':'  
								+ REPLICATE('0',2 - LEN(CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_end_time % 10000)/100))) 
								+ RTRIM(CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_end_time % 10000)/100))
								+ ' AM'
							WHEN (msdb.dbo.sysschedules.active_end_time % 1000000)/10000 < 12
								THEN CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_end_time % 1000000)/10000) 
								+ ':'  
								+ REPLICATE('0',2 - LEN(CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_end_time % 10000)/100))) 
								+ RTRIM(CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_end_time % 10000)/100))
								+ ' AM'
							WHEN (msdb.dbo.sysschedules.active_end_time % 1000000)/10000< 22
								THEN CONVERT(CHAR(1),((msdb.dbo.sysschedules.active_end_time % 1000000)/10000) - 12)
								+ ':'  
								+ REPLICATE('0',2 - LEN(CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_end_time % 10000)/100))) 
								+ RTRIM(CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_end_time % 10000)/100)) 
								+ ' PM'
							ELSE CONVERT(CHAR(2),((msdb.dbo.sysschedules.active_end_time % 1000000)/10000) - 12)
								+ ':'  
								+ REPLICATE('0',2 - LEN(CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_end_time % 10000)/100))) 
								+ RTRIM(CONVERT(CHAR(2),(msdb.dbo.sysschedules.active_end_time % 10000)/100)) 
								+ ' PM'
						END
				ELSE ''
		END, '')
		, [OnFailureNotify] = CASE WHEN msdb.dbo.sysjobs.notify_level_email = 2 THEN msdb.dbo.sysoperators.name END
		, [Description] = msdb.dbo.sysjobs.[description]
		, [OutputFile] = CASE WHEN l.LogCount != 1 THEN 'Check Logs'
								ELSE l.LogPath
							END
FROM	msdb.dbo.sysjobs
		LEFT OUTER JOIN msdb.dbo.sysjobschedules ON msdb.dbo.sysjobs.job_id = msdb.dbo.sysjobschedules.job_id
		LEFT OUTER JOIN  msdb.dbo.sysschedules
			ON msdb.dbo.sysjobschedules.schedule_id = msdb.dbo.sysschedules.schedule_id
		LEFT OUTER JOIN msdb.dbo.sysoperators ON msdb.dbo.sysjobs.notify_email_operator_id = msdb.dbo.sysoperators.id
		LEFT OUTER JOIN (
			SELECT  job_id
					,StepCount = COUNT(*)
					,LogCount = COUNT(DISTINCT output_file_name)
					,LogPath = MAX(output_file_name)
			FROM    msdb.dbo.sysjobsteps
			GROUP BY job_id
		) l ON l.job_id = sysjobs.job_id;
  "
  #write-host $sql_jobdata
  
  #Run SQL and capture results in array
  if ($servername -like "*MORNINGSTAR.COM")
  {
    $dt += Invoke-Sqlcmd -ServerInstance $servername -Query $sql_jobdata -QueryTimeout $QueryTimeout -Username $UtilUser -Password $UtilPwd
  } else
  {
    $dt += Invoke-Sqlcmd -ServerInstance $servername -Query $sql_jobdata -QueryTimeout $QueryTimeout
  }
}
#$dt | select-object

#Load data
$SqlConnection = new-object System.Data.SqlClient.SqlConnection
$SqlConnection.ConnectionString = "Server=$DBServer; Database=$DBName; Integrated Security=SSPI;"
$SqlConnection.Open()
$SqlCommand = new-object System.Data.SqlClient.SqlCommand
$SqlCommand.Connection = $SqlConnection

foreach ($dtrow in $dt)
{
  If ($dtrow.ServerName) #Skip NULL/empty records
  {
    $SqlInsert = "INSERT dbo.SQLAgentJobs(ServerName,JobName,JobSteps,Enabled,Schedule,OnFailureNotify,Description,OutputFile) VALUES('$($dtrow.ServerName)','$($dtrow.JobName)',$($dtrow.JobSteps),$($dtrow.Enabled),'$($dtrow.Schedule)','$($dtrow.OnFailureNotify)','$($dtrow.Description)','$($dtrow.OutputFile)')" 
    #write-output $SqlInsert
    $SqlCommand.CommandText = $SqlInsert
    $SqlCommand.ExecuteNonQuery()
  }
}

$SqlConnection.Close()
