function global:Get-GitWorktree {
    <#
    .SYNOPSIS
    Lists all git worktrees in the current repository and returns them as PowerShell objects.

    .DESCRIPTION
    Executes `git worktree list` and parses the output into PowerShell objects.
    Returns information about each worktree including path, commit hash, branch/detached status,
    and whether it's prunable.

    .PARAMETER Path
    The root path of the git repository. Defaults to current directory.

    .EXAMPLE
    Get-GitWorktree
    Lists all worktrees in the current git repository

    .EXAMPLE
    Get-GitWorktree -Path "C:\path\to\repo"
    Lists all worktrees in the specified repository

    .EXAMPLE
    Get-GitWorktree | Where-Object { $_.IsPrunable }
    List only prunable worktrees

    .OUTPUTS
    PSCustomObject with properties: Path, CommitHash, Branch, IsDetached, IsPrunable
    #>
    
    [CmdletBinding()]
    param(
        [string]$Path = "."
    )

    # Resolve to absolute path and verify git repo
    $absolutePath = Resolve-Path $Path -ErrorAction Stop
    
    # Check if in git repository
    Push-Location $absolutePath
    try {
        $null = & git rev-parse --git-dir 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Not a git repository"
            return
        }
    }
    finally {
        Pop-Location
    }

    $repoRoot = $null
    try {
        $repoRoot = & git rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $repoRoot) {
            $repoRoot = (Resolve-Path -LiteralPath $repoRoot).Path
        }
    }
    catch {
        $repoRoot = $null
    }

    $worktrees = @()

    try {
        $output = & git worktree list

        if (!$output) {
            Write-Warning "No worktrees found"
            return
        }

        <#
        Standard format:
        /path/to/repo                    abc123def [main]
        /path/to/worktree                def456ghi [feature-branch]
        /path/to/detached                ghi789jkl (detached)
        /path/to/prunable                jkl012mno (prunable)
        #>
        foreach ($line in $output) {
            if ($line -match '^\s*(.+?)\s{2,}([a-f0-9]+)\s+(\[(.+?)\]|\((.+?)\))') {
                $path = $Matches[1]
                $commitHash = $Matches[2]
                $status = $Matches[4] + $Matches[5]  # Either the branch name or status
                
                $isDetached = $status -eq "detached"
                $isPrunable = $status -eq "prunable"
                $branch = if (!$isDetached -and !$isPrunable) { $status } else { $null }
                
                $isMain = $false
                if ($repoRoot) {
                    try {
                        $resolvedPath = (Resolve-Path -LiteralPath $path).Path
                        $isMain = [string]::Equals($resolvedPath, $repoRoot, [System.StringComparison]::OrdinalIgnoreCase)
                    }
                    catch {
                        $isMain = $false
                    }
                }

                $o = [PSCustomObject]@{
                    Path       = $path
                    CommitHash = $commitHash
                    Branch     = $branch
                    IsDetached = $isDetached
                    IsPrunable = $isPrunable
                    IsMain     = $isMain
                }
                Write-Output $o
            }
        }
    }
    catch {
        Write-Error "Failed to list git worktrees: $_"
    }
}

function global:Set-LocationEx {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipelineByPropertyName = $true)]
        [string]$Path,

        [switch]$PassThru
    )

    if ($Path -match '^wt:[\\/]?(.*)$') {
        $normalized = $Matches[1].Trim('\', '/')

        $currentRelativePath = $null
        try {
            $currentRoot = & git rev-parse --show-toplevel 2>$null
            if ($LASTEXITCODE -eq 0 -and $currentRoot) {
                $currentRoot = (Resolve-Path -LiteralPath $currentRoot).Path
                $currentLocation = (Resolve-Path -LiteralPath (Get-Location).Path).Path
                if ($currentLocation -like "$currentRoot*") {
                    $suffix = $currentLocation.Substring($currentRoot.Length).TrimStart('\', '/')
                    if ($suffix) {
                        $currentRelativePath = $suffix
                    }
                }
            }
        }
        catch {
            $currentRelativePath = $null
        }

        if (-not $normalized) {
            $main = Get-GitWorktree | Where-Object { $_.IsMain } | Select-Object -First 1
            if ($null -ne $main) {
                $destination = $main.Path
                if ($currentRelativePath) {
                    $candidate = Join-Path -Path $main.Path -ChildPath $currentRelativePath
                    if (Test-Path -LiteralPath $candidate) {
                        $destination = $candidate
                    }
                    else {
                        Write-Warning "Subdirectory not found in target worktree: $currentRelativePath"
                    }
                }
                Microsoft.PowerShell.Management\Set-Location -Path $destination -PassThru:$PassThru
            }
            return
        }

        $segments = $normalized -split '[\\/]'
        $worktreeName = $segments[0]
        $relativePath = ($segments | Select-Object -Skip 1) -join [System.IO.Path]::DirectorySeparatorChar

        $worktrees = Get-GitWorktree
        if (-not $worktrees) {
            return
        }

        $target = $worktrees | Where-Object {
            (Split-Path -Leaf $_.Path) -like "*$worktreeName*"
        } | Select-Object -First 1

        if ($null -eq $target) {
            Write-Error "Worktree not found: $worktreeName"
            return
        }

        $destination = if ($relativePath) {
            Join-Path -Path $target.Path -ChildPath $relativePath
        }
        elseif ($currentRelativePath) {
            $candidate = Join-Path -Path $target.Path -ChildPath $currentRelativePath
            if (Test-Path -LiteralPath $candidate) {
                $candidate
            }
            else {
                Write-Warning "Subdirectory not found in target worktree: $currentRelativePath"
                $target.Path
            }
        }
        else {
            $target.Path
        }
        Microsoft.PowerShell.Management\Set-Location -Path $destination -PassThru:$PassThru
        return
    }

    Microsoft.PowerShell.Management\Set-Location @PSBoundParameters
}

function global:Get-ChildItemEx {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipelineByPropertyName = $true)]
        [string]$Path = "."
    )

    if ($Path -match '^wt:[\\/]?(.*)$') {
        $normalized = $Matches[1].Trim('\', '/')

        if (-not $normalized) {
            Get-GitWorktree | ForEach-Object {
                $name = if ($_.IsMain) { '\' } else { Split-Path -Leaf $_.Path }
                $fullName = if ($_.IsMain) { 'wt:\' } else { "wt:\$name" }
                [PSCustomObject]@{
                    PSChildName = $name
                    Mode        = 'd----'
                    Name        = $name
                    FullName    = $fullName
                    Branch      = $_.Branch
                    CommitHash  = $_.CommitHash
                    IsDetached  = $_.IsDetached
                    IsPrunable  = $_.IsPrunable
                    IsMain      = $_.IsMain
                }
            }
            return
        }

        $segments = $normalized -split '[\\/]'
        $worktreeName = $segments[0]
        $relativePath = ($segments | Select-Object -Skip 1) -join [System.IO.Path]::DirectorySeparatorChar

        $worktrees = Get-GitWorktree
        if (-not $worktrees) {
            return
        }

        $target = $worktrees | Where-Object {
            (Split-Path -Leaf $_.Path) -like "*$worktreeName*"
        } | Select-Object -First 1

        if ($null -eq $target) {
            Write-Error "Worktree not found: $worktreeName"
            return
        }

        $destination = if ($relativePath) { Join-Path -Path $target.Path -ChildPath $relativePath } else { $target.Path }
        Microsoft.PowerShell.Management\Get-ChildItem -Path $destination
        return
    }

    Microsoft.PowerShell.Management\Get-ChildItem @PSBoundParameters
}

Register-ArgumentCompleter -CommandName Set-LocationEx, Set-Location, cd, Get-ChildItemEx, Get-ChildItem, ls, dir -ParameterName Path -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    if ($wordToComplete -notlike 'wt:*') {
        return
    }

    $prefix = if ($wordToComplete -match '^wt:[\\/]?(.*)') { $Matches[1] } else { '' }

    if (-not $prefix) {
        [System.Management.Automation.CompletionResult]::new(
            'wt:\',
            'wt:\',
            'ProviderContainer',
            'Main worktree'
        )
    }

    Get-GitWorktree | ForEach-Object {
        $name = Split-Path -Leaf $_.Path
        if ($name -like "$prefix*") {
            $completionText = "wt:\$name"
            $listText = $name
            $tooltip = if ($_.Branch) { "$($_.Branch) - $($_.CommitHash)" } else { $_.CommitHash }

            [System.Management.Automation.CompletionResult]::new(
                $completionText,
                $listText,
                'ProviderItem',
                $tooltip
            )
        }
    }
}

Set-Alias -Name cd -Value Set-LocationEx -Option AllScope -Scope Global
Set-Alias -Name ls -Value Get-ChildItemEx -Option AllScope -Scope Global
Set-Alias -Name dir -Value Get-ChildItemEx -Option AllScope -Scope Global


New-Alias "git-wt" Get-GitWorktree -Scope Global -Force