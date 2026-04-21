# Git Worktree PowerShell Provider Implementation Plan

## 1. IMPLEMENTATION OPTIONS

### Option A: Full PSProvider Implementation (NavigationCmdletProvider)
**Complexity:** High  
**Capabilities:** Full navigation support

This involves creating a C# or PowerShell class that inherits from provider base classes:

- **ItemCmdletProvider** - Basic item operations (Get-Item, Clear-Item, Invoke-Item)
- **ContainerCmdletProvider** - Container operations (Get-ChildItem, New-Item, Remove-Item, Rename-Item, Copy-Item)
- **NavigationCmdletProvider** - Path navigation (Move-Item, Join-Path, Split-Path, relative paths)

**Pros:**
- Native PowerShell integration - all cmdlets work seamlessly
- Full tab completion support built-in
- Proper path parsing and resolution
- Can implement custom item properties
- Supports filtering, wildcards, `-Recurse`

**Cons:**
- Requires C# compilation or PowerShell classes (complex)
- Must implement ~15-20 methods for full functionality
- Steep learning curve
- More challenging to debug
- Requires module manifest with provider registration

**Key Methods to Implement:**
```powershell
GetItem(), GetChildItems(), ItemExists(), IsValidPath()
GetChildName(), GetParentPath(), MakePath(), NormalizeRelativePath()
```

### Option B: SHiPS (Simple Hierarchy in PowerShell)
**Complexity:** Medium  
**Capabilities:** Simplified provider creation

SHiPS is a Microsoft framework specifically designed to make provider creation easier for hierarchical data.

**Status in Workspace:** Not found installed

**Pros:**
- PowerShell-only (no C# required)
- Simplified API - inherit from `[SHiPS.PowerShell.SHiPSDirectory]` and `[SHiPS.PowerShell.SHiPSLeaf]`
- Built-in navigation support
- Active community examples (Azure Cloud Shell uses it)
- Much less boilerplate code

**Cons:**
- External dependency (requires `Install-Module SHiPS`)
- Less control than full provider
- Still requires understanding provider concepts
- Performance overhead for large hierarchies

**Example Structure:**
```powershell
class WorktreeRoot : SHiPS.PowerShell.SHiPSDirectory {
    [object[]] GetChildItem() {
        # Return worktree objects
    }
}
```

### Option C: New-PSDrive with Script-Based Navigation
**Complexity:** Low to Medium  
**Capabilities:** Limited but quick

Use `New-PSDrive` with PowerShell's FileSystem provider, creating symbolic structure or wrapper functions.

**Pros:**
- Quick prototype
- Familiar PowerShell scripting
- No provider implementation needed
- Can leverage existing filesystem capabilities

**Cons:**
- **Major Limitation:** Can't create custom child items within `wt:\`
- Limited to filesystem semantics
- No native container support
- Navigation requires workarounds
- `cd wt:\myworktree` won't work natively - would need proxy functions

**Approach:**
```powershell
New-PSDrive -Name wt -PSProvider FileSystem -Root $someTemporaryRoot
# Then populate with junction points or proxy navigation
```

### Option D: Function-Based "Virtual Drive" (Hybrid Approach)
**Complexity:** Low  
**Capabilities:** Good balance for this use case

Override or wrap navigation cmdlets to intercept `wt:` paths.

**Pros:**
- No true provider needed
- Can implement exactly what you need
- Easy to maintain and debug
- Tab completion via ArgumentCompleter
- Flexible control flow

**Cons:**
- Not a "real" drive (won't show in `Get-PSDrive`)
- Requires wrapping/proxying cmdlets
- Some cmdlets might not work
- Manual path parsing

**Implementation Pattern:**
```powershell
function Set-LocationEx {
    if ($Path -match '^wt:[\\/](.+)') {
        $worktreeName = $Matches[1]
        $worktrees = Get-GitWorktree
        $target = $worktrees | Where-Object { $_.Path -match $worktreeName }
        Set-Location $target.Path
    } else {
        Set-Location @PSBoundParameters
    }
}
```

## 2. EXISTING EXAMPLES IN WORKSPACE

**Finding:** No provider implementations found in your workspace.

**Modules Examined:**
- **posh-git** - Tab completion and prompt customization only
- **cd-extras** - Enhanced navigation via command-not-found handler
- **PathUtils** - Path manipulation utilities
- **GitWorktree** - Empty folder (placeholder?)

**Relevant Pattern:** The `cd-extras` module shows an interesting approach using `CommandNotFoundAction` to intercept commands, which could be adapted for the hybrid approach.

## 3. KEY TECHNICAL CHALLENGES

### Challenge 1: Aggregating Worktrees
**Issue:** Deciding scope - current repo vs. multiple repos

**Solutions:**
- **Current repo only:** Simpler, use `Get-GitWorktree` from current location
- **Multiple repos:** Need a registry of git repositories to scan
  - Configuration file with repo paths
  - Scan common locations (Documents, Repos folders)
  - Environment variable with repo list
  - Cache results for performance

### Challenge 2: Making Worktrees Appear as Children
**Issue:** `ls wt:` should show worktree names, not physical filesystem

**Solutions:**
- With provider: Implement `GetChildItems()` to return custom PSObjects representing each worktree
- With hybrid: Create wrapper for `Get-ChildItem` that detects `wt:` and calls `Get-GitWorktree`

### Challenge 3: Path Resolution
**Issue:** Mapping `wt:\feature-branch` to actual filesystem path

**Solutions:**
- Maintain in-memory hashtable: `worktreeName -> actualPath`
- Parse worktree names from paths (branch names may contain slashes)
- Handle ambiguity if multiple worktrees match
- Handle special chars in branch names

### Challenge 4: Tab Completion
**Issue:** Enabling completion for worktree names

**Solutions:**
- With provider: Automatic via `GetChildItems()`
- Without provider: Register `ArgumentCompleter`:
```powershell
Register-ArgumentCompleter -CommandName Set-Location -ParameterName Path -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    if ($wordToComplete -like 'wt:*') {
        Get-GitWorktree | ForEach-Object {
            $name = Split-Path -Leaf $_.Path
            [System.Management.Automation.CompletionResult]::new(
                "wt:\$name", $name, 'ProviderContainer', $_.Branch
            )
        }
    }
}
```

### Challenge 5: Performance
**Issue:** Running `git worktree list` on every operation

**Solutions:**
- Cache worktree list with TTL (e.g., 30 seconds)
- Invalidate cache on git operations
- Background refresh
- Only scan on explicit operations, not every path resolution

### Challenge 6: Error Handling
**Issue:** User navigates to `wt:` outside a git repository

**Solutions:**
- Return empty list
- Show helpful error message
- Allow configuration of "watched" repositories

## 4. RECOMMENDED APPROACH

**For Your Use Case: Hybrid Function-Based Approach**

### Rationale:
1. **Appropriate complexity** - Full provider is overkill for this relatively simple scenario
2. **Quick implementation** - Can build on existing `Get-GitWorktree` function
3. **Maintainable** - Pure PowerShell, easy to debug and modify
4. **Sufficient functionality** - Delivers the core scenarios you described
5. **No dependencies** - No need to install SHiPS or write C#

### Implementation Plan:

#### Phase 1: Core Navigation (Minimal Viable Product)
```powershell
# Extend Set-Location to handle wt: paths
function Set-LocationEx {
    param([string]$Path, [switch]$PassThru)
    
    if ($Path -match '^wt:[\\/]?(.*)') {
        $worktreeName = $Matches[1]
        if (-not $worktreeName) {
            # cd wt: -> show list or go to main worktree
            Get-GitWorktree | Format-Table
            return
        }
        
        $worktrees = Get-GitWorktree
        $target = $worktrees | Where-Object { 
            (Split-Path -Leaf $_.Path) -like "*$worktreeName*" 
        } | Select-Object -First 1
        
        if ($target) {
            Set-Location $target.Path -PassThru:$PassThru
        } else {
            Write-Error "Worktree not found: $worktreeName"
        }
    } else {
        Microsoft.PowerShell.Management\Set-Location @PSBoundParameters
    }
}
Set-Alias -Name cd -Value Set-LocationEx -Option AllScope -Scope Global
```

#### Phase 2: List Support
```powershell
function Get-ChildItemEx {
    param([string]$Path = ".")
    
    if ($Path -match '^wt:[\\/]?(.*)') {
        $subPath = $Matches[1]
        if (-not $subPath) {
            # ls wt: -> list worktrees as directories
            Get-GitWorktree | ForEach-Object {
                $name = Split-Path -Leaf $_.Path
                [PSCustomObject]@{
                    PSChildName = $name
                    Mode = 'd----'
                    Name = $name
                    FullName = "wt:\$name"
                    Branch = $_.Branch
                    CommitHash = $_.CommitHash
                }
            }
        } else {
            # ls wt:\feature -> list contents of that worktree
            # Resolve and delegate to real path
            $worktrees = Get-GitWorktree
            $target = $worktrees | Where-Object { 
                (Split-Path -Leaf $_.Path) -like "*$subPath*" 
            } | Select-Object -First 1
            
            if ($target) {
                Get-ChildItem $target.Path
            }
        }
    } else {
        Microsoft.PowerShell.Management\Get-ChildItem @PSBoundParameters
    }
}
Set-Alias -Name ls -Value Get-ChildItemEx -Option AllScope -Scope Global
Set-Alias -Name dir -Value Get-ChildItemEx -Option AllScope -Scope Global
```

#### Phase 3: Tab Completion
```powershell
Register-ArgumentCompleter -CommandName Set-LocationEx,Set-Location,cd -ParameterName Path -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    
    if ($wordToComplete -like 'wt:*') {
        $prefix = if ($wordToComplete -match '^wt:[\\/]?(.*)') { $Matches[1] } else { '' }
        
        Get-GitWorktree | ForEach-Object {
            $name = Split-Path -Leaf $_.Path
            if ($name -like "$prefix*") {
                $completionText = "wt:\$name"
                $listText = $name
                $tooltip = "$($_.Branch) - $($_.CommitHash)"
                
                [System.Management.Automation.CompletionResult]::new(
                    $completionText, $listText, 'ProviderContainer', $tooltip
                )
            }
        }
    }
}
```

### When to Upgrade to SHiPS:
Consider SHiPS if you later want:
- Multiple levels (e.g., `wt:\project1\feature-branch\`)
- Complex hierarchical data
- Rich item properties
- Full cmdlet ecosystem support

### When to Upgrade to Full Provider:
Consider full provider if you need:
- Integration with third-party tools expecting standard providers
- Performance-critical scenarios (compiled code)
- Advanced features (item properties, transactions, credentials)
- Distribution as a professional module

## NEXT STEPS

1. **Prototype the hybrid approach** - Start with Phase 1 (15-30 minutes)
2. **Test edge cases** - Non-git directories, naming conflicts, special characters
3. **Add caching** - Cache `Get-GitWorktree` results for performance
4. **Implement phases 2 & 3** - List and completion support
5. **Consider multi-repo** - Add configuration for watched repositories if needed

**Estimated Implementation Time:**
- Phase 1: 30 minutes
- Phase 2: 1 hour
- Phase 3: 30 minutes
- Polish & edge cases: 1-2 hours
- **Total: 3-4 hours for complete solution**

This approach gives you 80% of the functionality with 20% of the complexity compared to a full provider implementation.
