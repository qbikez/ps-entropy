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
                
                $o = [PSCustomObject]@{
                    Path       = $path
                    CommitHash = $commitHash
                    Branch     = $branch
                    IsDetached = $isDetached
                    IsPrunable = $isPrunable
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
        $worktreeName = $Matches[1]

        if (-not $worktreeName) {
            Get-GitWorktree | Format-Table Path, Branch, CommitHash, IsDetached, IsPrunable
            return
        }

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

        Microsoft.PowerShell.Management\Set-Location -Path $target.Path -PassThru:$PassThru
        return
    }

    Microsoft.PowerShell.Management\Set-Location @PSBoundParameters
}

Set-Alias -Name cd -Value Set-LocationEx -Option AllScope -Scope Global


New-Alias "git-wt" Get-GitWorktree -Scope Global -Force