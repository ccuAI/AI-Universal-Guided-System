# AI 就醫夥伴：把引導伺服器部署到 Google Cloud Run
#
# 用法（在 backfront/guide-server 資料夾執行）：
#   .\deploy-cloudrun.ps1 -Project 你的GCP專案ID
#
# 會從這個資料夾的 .env 讀出 AI 設定（GUIDE_AI_*、GUIDE_ACCESS_TOKEN…），
# 用 Cloud Run 的環境變數傳上去；.env 檔案本身不會被上傳（見 .gcloudignore）。

param(
    [Parameter(Mandatory = $true)][string]$Project,
    [string]$Region = "asia-east1",          # 台灣機房
    [string]$Service = "ai-hospital-guide"
)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$envFile = Join-Path $here ".env"

if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
    Write-Host "找不到 gcloud。請先安裝 Google Cloud CLI：https://cloud.google.com/sdk/docs/install" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $envFile)) {
    Write-Host "找不到 .env，請先複製 .env.example 成 .env 並填入金鑰" -ForegroundColor Red
    exit 1
}

# 讀 .env：只取需要的設定，略過註解、空值和本機用的 GUIDE_PORT
$vars = @()
foreach ($line in Get-Content $envFile -Encoding UTF8) {
    $t = $line.Trim()
    if ($t -eq "" -or $t.StartsWith("#")) { continue }
    $i = $t.IndexOf("=")
    if ($i -lt 1) { continue }
    $key = $t.Substring(0, $i).Trim()
    $value = $t.Substring($i + 1).Trim()
    if ($key -eq "GUIDE_PORT" -or $value -eq "") { continue }
    if ($key -notlike "GUIDE_*") { continue }
    $vars += "$key=$value"
}
if (-not ($vars | Where-Object { $_ -like "GUIDE_AI_API_KEY=*" })) {
    Write-Host ".env 裡的 GUIDE_AI_API_KEY 是空的" -ForegroundColor Red
    exit 1
}

Write-Host ("要上傳的設定：" + (($vars | ForEach-Object { $_.Split("=")[0] }) -join ", "))
if (-not ($vars | Where-Object { $_ -like "GUIDE_ACCESS_TOKEN=*" })) {
    Write-Host "提醒：沒有設定 GUIDE_ACCESS_TOKEN（通行碼），任何知道網址的人都能使用（仍有次數上限）" -ForegroundColor Yellow
}

# 備援模型清單裡有逗號，所以用 ^@^ 改成以 @ 分隔
$envArg = "^@^" + ($vars -join "@")

gcloud run deploy $Service `
    --source $here `
    --project $Project `
    --region $Region `
    --allow-unauthenticated `
    --min-instances 0 `
    --max-instances 1 `
    --memory 512Mi `
    --timeout 60 `
    --set-env-vars $envArg

if ($LASTEXITCODE -eq 0) {
    $url = gcloud run services describe $Service --project $Project --region $Region --format "value(status.url)"
    Write-Host ""
    Write-Host "部署完成！網址：$url" -ForegroundColor Green
    Write-Host "測試：在瀏覽器打開 $url/health ，看到 {""ok"":true…} 就成功了"
}
