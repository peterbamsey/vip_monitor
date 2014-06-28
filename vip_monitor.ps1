#A Powershell port of the vip_monitor.sh script here https://aws.amazon.com/articles/Amazon-EC2/2127188135977316
# This script will monitor another HA node and take over a Virtual IP (VIP)
# if communication with the other node fails

# High Availability IP variables
# Other node's IP to ping and VIP to swap if other node goes down
$HA_Node_IP="172.16.0.202"
$Host_IP="172.16.0.201"
$VIP="172.16.0.200"

# Determine the instance and ENI IDs so we can reassign the VIP to the
# correct ENI.  Requires EC2 describe-instances and assign-private-ip-address
# permissions.  The following example EC2 Roles policy will authorize these
# commands:
#{
# "Statement": [
# {
# "Action": [
# "ec2:AssignPrivateIpAddresses",
# "ec2:DescribeInstances",
# "ec2:DescribeNetworkInterfaces",
# "ec2:UnassignPrivateIpAddresses"
# ],
# "Effect": "Allow",
# "Resource": "*"
# }
# ]
#}

$instance_id=(invoke-restmethod -uri http://169.254.169.254/latest/meta-data/instance-id)

#Create a filter to locate the ENI of this host
$filterName = new-object Amazon.Ec2.Model.Filter
$filterName.name = "attachment.instance-id"
$filterName.value = $instance_id
$ENI_ID=(Get-EC2NetworkInterface -Filters $filtername | Select-Object -expand NetworkInterfaceId)

$(Get-Date -Format o) + $(" -- Starting HA monitor") >> C:\users\HA_log.txt

#Make sure this host doesn't have the VIP on startup - assume on startup node is never master
$(Get-Date -Format o) + $(" Setting Node only IP") >> C:\users\HA_log.txt
$wmi = Get-WmiObject win32_networkadapterconfiguration -filter "ipenabled = 'true'"
$subnet = @("255.255.255.0")
$wmi.EnableStatic($Host_Ip, $subnet)
$wmi.SetGateways("172.16.0.1", 1)
$wmi.SetDNSServerSearchOrder("172.16.1.100")

while($true){
  $pingresult=(ping -n 3 -w 1 $HA_Node_IP | select-string "TTL" | foreach { %{$_.Line.Split(" ")}} | select-string "TTL" | measure-object -line | select-object -expand Lines)
  Write-Host $pingresult
  if($pingresult -eq "0"){
    $(Get-Date -Format o) + $(" -- HA heartbeat failed, taking over VIP") >> C:\users\HA_log.txt
    Register-EC2PrivateIpAddress -NetworkInterfaceId $ENI_ID -PrivateIpAddresses $VIP -Allowreassignment $true
    Start-Sleep -seconds 15
    $wmi = Get-WmiObject win32_networkadapterconfiguration -filter "ipenabled = 'true'"
    $ip = @($Host_IP, $VIP)
    $subnet = @("255.255.255.0","255.255.255.0")
    $wmi.EnableStatic($ip, $subnet)
    $wmi.SetGateways("172.16.0.1", 1)
    $wmi.SetDNSServerSearchOrder("172.16.1.100")
    $pingresult=(ping -n 1 -w 1 $VIP | select-string "time<" | foreach { %{$_.Line.Split(" ")}} | select-string "time<" | measure-object -line | select-object -expand Lines)
	Start-Sleep -seconds 10
  }
  else{
	#This grows the log file and we should probably truncate it at some point
    $(Get-Date -Format o) + $(" -- Heartbeat is good " +$pingresult) >> C:\users\HA_log.txt
  }
  Start-Sleep -seconds 2
}
