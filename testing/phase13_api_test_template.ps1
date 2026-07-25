param([Parameter(Mandatory=$true)][string]$Token,[string]$Api='https://udrive-api-production.up.railway.app')
$h=@{Authorization="Bearer $Token";Accept='application/json'}
Invoke-RestMethod "$Api/health/live"
Invoke-RestMethod "$Api/health/ready"
Invoke-RestMethod "$Api/api/v1/admin/finance/dashboard" -Headers $h
Invoke-RestMethod "$Api/api/v1/admin/finance/transactions?page=1&pageSize=25" -Headers $h
Invoke-RestMethod "$Api/api/v1/admin/finance/earnings" -Headers $h
Invoke-RestMethod "$Api/api/v1/admin/finance/wallets" -Headers $h
Invoke-RestMethod "$Api/api/v1/admin/finance/payouts" -Headers $h
Invoke-RestMethod "$Api/api/v1/admin/finance/refunds" -Headers $h
Invoke-RestMethod "$Api/api/v1/admin/finance/commission-rules" -Headers $h
