# <#
# .Synopsis 
# Stores an object in in-memory cache. The object is valid as long as lockfile has not changed
# #>
# function set-cachedobject([Parameter(Mandatory=$true)]$lockfile, [Parameter(Mandatory=$true)]$object) {
#     if (!(test-path $lockfile)) { throw "lock file '$lockfile' not found" }
#     $f = gi $lockfile
#     $ts = $f.LastWriteTimeUtc
#     $global:cache[$lockfile] = @{
#         ts = $ts
#         value = $object
#         file = (gi $lockfile).FullName
#     }
# }

# <#
# .Synopsis 
# Returns an object from in-memory cache that is locked by specified lockfile.
# If lockfile was modified since the object was cached, returns $null.
# #>
# function get-cachedobject([Parameter(Mandatory=$true)]$lockfile) {
#     if (!(test-path $lockfile)) { throw "lock file '$lockfile' not found" }
#     if ($global:cache[$lockfile] -ne $null) {
#         $f = gi $lockfile
#         $ts = $f.LastWriteTimeUtc
#         if ($ts -le $global:cache[$lockfile].ts)  {
#             return $global:cache[$lockfile]
#         }
#     }
#     return $null
# }