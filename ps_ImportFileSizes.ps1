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
		,ISNULL(MAX(fs.AsOfDate),'1/1/1980') AS ReportDate
FROM	dbo.ServerList sl
		LEFT OUTER JOIN dbo.DBFileSizes fs ON fs.ServerName = sl.HostName
WHERE	sl.Import = 1
AND		sl.Active = 1
GROUP BY sl.HostName
		,sl.ServerName + '.' + sl.Domain;
"

#To Do If Invoke-SqlCmd Is Not Recognized in Windows PowerShell
Add-PSSnapin SqlServerCmdletSnapin100
Add-PSSnapin SqlServerProviderSnapin100

$servers = Invoke-Sqlcmd -ServerInstance $DBServer -Database $DBName -Query $sql_serverlist
#$servers | select-object

#Setup DataTable
$dt = new-object Data.DataTable
$col1 = new-object Data.DataColumn ServerName,([string])
$col2 = new-object Data.DataColumn DatabaseName,([string])
$col3 = new-object Data.DataColumn AsOfDate,([datetime])
$col4 = new-object Data.DataColumn Filegroup,([string])
$col5 = new-object Data.DataColumn Size_MB,([int])
$col6 = new-object Data.DataColumn Free_MB,([int])
$col7 = new-object Data.DataColumn PctFree,([decimal])
$col8 = new-object Data.DataColumn VLFs,([int])
$col9 = new-object Data.DataColumn FileName,([string])
$col10 = new-object Data.DataColumn Growth,([int])
$dt.columns.add($col1)
$dt.columns.add($col2)
$dt.columns.add($col3)
$dt.columns.add($col4)
$dt.columns.add($col5)
$dt.columns.add($col6)
$dt.columns.add($col7)
$dt.columns.add($col8)
$dt.columns.add($col9)
$dt.columns.add($col10)

#Loop through servers and pull in bak file data
foreach($server in $servers)
{
  #Retrieve ServerName and MAX(ReportDate) from array
  $hostname = $server[0]
  $servername = $server[1]
  $reportdate = $server[2].ToString()

  #Build SQL to retrieve records for import
  $sql_bakdata="
  SELECT  '$hostname' AS ServerName
           ,DatabaseName
           ,AsOfDate
           ,Filegroup
           ,Size_MB
           ,Free_MB
           ,PctFree
           ,VLFs
           ,FileName
           ,Growth
  FROM	rp_util.dbo.DBFileSizes
  WHERE	CAST(AsOfDate AS SMALLDATETIME) > '$reportdate';
  "
  #write-host $sql_bakdata
  
  #Run SQL and capture results in array
  if ($servername -like "*MORNINGSTAR.COM")
  {
    $dt += Invoke-Sqlcmd -ServerInstance $servername -Query $sql_bakdata -QueryTimeout $QueryTimeout -Username $UtilUser -Password $UtilPwd
  } else
  {
    $dt += Invoke-Sqlcmd -ServerInstance $servername -Query $sql_bakdata -QueryTimeout $QueryTimeout
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
    $SqlInsert = "INSERT dbo.DBFileSizes(ServerName,DatabaseName,Filegroup,Size_MB,Free_MB,PctFree,AsOfDate,VLFs,FileName,Growth) VALUES('$($dtrow.ServerName)','$($dtrow.DatabaseName)','$($dtrow.Filegroup)',$($dtrow.Size_MB),$($dtrow.Free_MB),$($dtrow.PctFree),'$($dtrow.AsOfDate)',$($dtrow.VLFs),'$($dtrow.FileName)',$($dtrow.Growth))" 
    #write-output $SqlInsert
    $SqlCommand.CommandText = $SqlInsert
    $SqlCommand.ExecuteNonQuery()
  }
}

$SqlConnection.Close()
