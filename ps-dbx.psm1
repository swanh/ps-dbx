#The beginning of the Dropbox PowerShell module, what purpose will it serve? i have no idea

#Prompt user to enter token, stored for remainder of sessions, will update to connect function later
$apitok = Read-Host -Prompt "Enter your API access key"

#Grab a list of all active (deleted,suspended will be added later)
#https://www.dropbox.com/developers/documentation/http/teams#team-members-list
function Get-DBUsers{
$uri = 'https://api.dropboxapi.com/2/team/members/list'
#need to add some filtering arguments, filter by name, email, account status, etc 
(Invoke-RestMethod -Uri $uri -Headers @{"Authorization" = "Bearer $apitok";"Content-Type" = "application/json"} -Method Post -Body (ConvertTo-Json -InputObject @{limit = 1000})).members.profile | Select-Object email,team_member_id,account_id,joined_on,groups
}

#Return a list of team folders, currently useless, possibly useless forever
#https://www.dropbox.com/developers/documentation/http/teams#team-team_folder-list
function Get-DBTeamFolders{
$uri = 'https://api.dropboxapi.com/2/team/team_folder/list'
(Invoke-RestMethod -Uri $uri -Headers @{"Authorization" = "Bearer $apitok";"Content-Type" = "application/json"} -Method Post -Body (ConvertTo-Json -InputObject @{limit = 1000})).team_folders
}

#Return a user's mountable folders (all folders shared with a user), need team member ID which can be found by running the Get-DBUser function
#https://www.dropbox.com/developers/documentation/http/documentation#sharing-list_mountable_folders
function Get-DBMountFolder{
param([parameter(Mandatory=$True)][string]$team_member_id)
$uri = 'https://api.dropboxapi.com/2/sharing/list_mountable_folders'
(Invoke-RestMethod -Uri $uri -Headers @{"Authorization" = "Bearer $apitok";"Content-Type" = "application/json";"Dropbox-API-Select-User" = $team_member_id} -Method Post -Body (ConvertTo-Json -InputObject @{limit = 1000})).entries
}

#Return files in user's Dropbox. 
#https://www.dropbox.com/developers/documentation/http/documentation#sharing-list_folders
#need to add recurive options
#need while loop for has_more property
function Get-DBUserFiles{
param(
[parameter(Mandatory=$True)][string]$team_member_id,
[string]$path)
$folders = @()
$files = @()
$uri = "https://api.dropboxapi.com/2/files/list_folder"
$uri2 = "https://api.dropboxapi.com/2/files/list_folder/continue"
$data = (Invoke-RestMethod -Uri $uri -Headers @{"Authorization" = "Bearer $apitok";"Content-Type" = "application/json";"Dropbox-API-Select-User" = $team_member_id} -Method Post -Body (ConvertTo-Json -InputObject @{path = "$path";recursive = $false;include_media_info = $false;include_deleted = $false;include_has_explicit_shared_members = $false}))
$cursor = $data.cursor
if($data.has_more){
$data2 = (Invoke-RestMethod -Uri $uri2 -Headers @{"Authorization" = "Bearer $apitok";"Content-Type" = "application/json";"Dropbox-API-Select-User" = $team_member_id} -Method Post -Body (ConvertTo-Json -InputObject @{cursor= "$cursor"}))
$results = $data.entries + $data2.entries
$results
}
else{$data.entries}
}

#Get folder size in gigabytes
function Get-DBFolderSize{
param(
[parameter(Mandatory=$True)][string]$team_member_id,
[string]$path)

$object = New-Object –TypeName PSObject
$object | Add-Member -MemberType NoteProperty -Name FullPath -Value @() 
$object | Add-Member -MemberType NoteProperty -Name Size -Value @()
[System.Collections.ArrayList]$folders = @()
$folders += $path

while($folders.Count -gt 0){
$data = Get-DBUserFiles -team_member_id $team_member_id -path $folders[0]
foreach($i in $data){
if($i.".tag" -eq "folder"){
$folders += $i.path_display
}
elseif($i.".tag" -eq "file"){
$object.Size += $i.size
$object.FullPath += $i.path_display 
}
}
$folders.RemoveAt(0)
}
($object.Size | Measure-Object -Sum).Sum / 1073741824 
}

#Returns ALL shared folders
function Get-DBSharedFileTree{Get-DBUsers | % {(Get-DBMountFolder -team_member_id $_.team_member_id).name} | Sort-Object | gu}

#Share folder with user. If you don't own the folder or have access to the folder, specify OwnerEmail as someone who does.  
function Share-DropboxFolder{
param(
[parameter(Mandatory=$true)][string]$UserEmail,
[parameter(Mandatory=$true)][string]$OwnerEmail,
[parameter(Mandatory=$true)][string]$FolderName
)
Write-Host "Getting Owner ID" -ForegroundColor Yellow
$ownerID = (Get-DBUsers | Where-Object {$_.email -eq $OwnerEmail}).team_member_id
Write-Host "OwnerID: " $ownerID -ForegroundColor Green
$uri1 = 'https://api.dropboxapi.com/2/sharing/list_folders'
Write-Host "Getting folder ID" -ForegroundColor Yellow
$shr_fld_id = (Invoke-RestMethod -Uri $uri1 -Headers @{"Authorization" = "Bearer $apitok";"Content-Type" = "application/json";"Dropbox-API-Select-User" = "$ownerID"} -Method Post -Body (ConvertTo-Json -InputObject @{limit = 1000})).entries | Where-Object {$_.name -eq $FolderName} | Select shared_folder_id
Write-Host "Folder ID is: " $shr_fld_id.shared_folder_id -ForegroundColor Green
$uri2 = 'https://api.dropboxapi.com/2/sharing/add_folder_member'
$body = @{members = @(@{'member' = @{'.tag' = 'email';'email' = $UserEmail};"access_level" = @{'.tag' = 'editor'}});shared_folder_id = $shr_fld_id.shared_folder_id}
$body | ConvertTo-Json -Depth 3 | Out-File "$env:USERPROFILE\dbtemp.json"
(Invoke-RestMethod -Uri $uri2 -Headers @{"Authorization" = "Bearer $apitok";"Content-Type" = "application/json";"Dropbox-API-Select-User" = "$ownerID"} -Method Post -Body (Get-Content "$env:USERPROFILE\dbtemp.json"))
Write-Host "Sharing folder" $FolderName "with" $UserEmail -ForegroundColor Yellow
Remove-Item "$env:USERPROFILE\dbtemp.json"
}

#untested
function Get-DBSharedFolderMembers{
param(
[parameter(Mandatory=$True)][string]$team_member_id,
[parameter(Mandatory=$True)][string]$shared_folder_id
)
$uri = "https://api.dropboxapi.com/2/sharing/list_folder_members"
(Invoke-RestMethod -Uri $uri -Headers @{"Authorization" = "Bearer $apitok";"Content-Type" = "application/json";"Dropbox-API-Select-User" = $team_member_id} -Method Post -Body (ConvertTo-Json -InputObject @{shared_folder_id = $shared_folder_id;limit = 1000}))
}
#needs cursor check to continue
function Get-DBGroups{
$uri = "https://api.dropboxapi.com/2/team/groups/list"
(Invoke-RestMethod -Uri $uri -Headers @{"Authorization" = "Bearer $apitok";"Content-Type" = "application/json"} -Method Post -Body (ConvertTo-Json -InputObject @{limit = 1000})).groups

}
#how to pass json list thru powershell?
function Get-DBGroupMembers([string]$GroupID){
$uri = "https://api.dropboxapi.com/2/team/groups/members/list"
(Invoke-RestMethod -Uri $uri -Headers @{"Authorization" = "Bearer $apitok";"Content-Type" = "application/json"} -Method Post -Body (ConvertTo-Json -InputObject @{limit = 1000;group = $GroupID}))
}

