@echo off
setlocal enabledelayedexpansion
REM Set PARAMNAMEPREFIX
setx PARAMNAMEPREFIX /RL/RG/secure-desktop/auth-token/
REM Get AWS metadata token
FOR /f "delims=" %%i in ('curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"') do set token=%%i
REM Get AWS region using the token
FOR /f "delims=" %%i in ('curl -s "http://169.254.169.254/latest/meta-data/placement/region" -H "X-aws-ec2-metadata-token: !token!"') do set region=%%i
REM Get instance ID using the token
FOR /f "delims=" %%i in ('curl -s "http://169.254.169.254/latest/meta-data/instance-id" -H "X-aws-ec2-metadata-token: !token!"') do set instance_id=%%i
REM Set session ID and generate auth token
set session_id=console
set auth_token=%random%-%random%-%random%-%random%-%random%
set parameter_name=/RL/RG/secure-desktop/auth-token/%instance_id%
REM Put parameter using AWS SSM
aws ssm put-parameter --name "%parameter_name%" --type "SecureString" --value "{\"auth_token\":\"%auth_token%\",\"session_id\":\"%session_id%\"}" --region "%region%" --overwrite
echo User token set successfully
