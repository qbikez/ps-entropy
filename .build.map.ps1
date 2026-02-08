@{
    "install" = {
        Write-Host "🔗 Installing PowerShell modules..." -ForegroundColor Cyan
        Write-Host ""
        
        # Find all .psd1 files in the repository
        Get-ChildItem -Path $PSScriptRoot -Recurse -Filter "*.psd1" | ForEach-Object {
            $moduleDir = $_.Directory.FullName
            $moduleName = $_.BaseName
            $targetPath = Join-Path "$env:UserProfile\Documents\PowerShell\Modules" $moduleName
            
            if (-not (Test-Path $targetPath)) {
                New-Item -ItemType Junction -Path $targetPath -Target $moduleDir | Out-Null
                Write-Host "  ✅ " -ForegroundColor Green -NoNewline
                Write-Host $moduleName -ForegroundColor White -NoNewline
                Write-Host " → " -ForegroundColor DarkGray -NoNewline
                Write-Host $moduleDir -ForegroundColor DarkGray
            }
            else {
                Write-Host "  ⏭️  " -ForegroundColor Yellow -NoNewline
                Write-Host $moduleName -ForegroundColor White -NoNewline
                Write-Host " (already exists)" -ForegroundColor DarkGray
            }
        }
        
        Write-Host ""
        Write-Host "✨ Installation complete!" -ForegroundColor Green
    }
}