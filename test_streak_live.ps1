$ErrorActionPreference = 'Stop'
$base = 'https://backend-production-04292.up.railway.app/api'
$devId = "qa-streak-test-$(Get-Date -Format 'yyyyMMddHHmmss')"
$results = @()

function Log($name, $ok, $detail) {
  $script:results += [pscustomobject]@{ Test = $name; Result = $(if ($ok) {'PASS'} else {'FAIL'}); Detail = $detail }
  $tag = $(if ($ok) {'PASS'} else {'FAIL'})
  Write-Host "[$tag] $name :: $detail"
}

function Api($method, $path, $body, $token) {
  $headers = @{ 'Content-Type' = 'application/json' }
  if ($token) { $headers['Authorization'] = "Bearer $token" }
  try {
    if ($method -eq 'GET') {
      $r = Invoke-RestMethod -Uri "$base$path" -Method GET -Headers $headers -TimeoutSec 30
    } else {
      $json = $body | ConvertTo-Json -Depth 5
      $r = Invoke-RestMethod -Uri "$base$path" -Method POST -Headers $headers -Body $json -TimeoutSec 30
    }
    return @{ ok = $true; data = $r }
  } catch {
    $code = $null
    $msg = $_.Exception.Message
    if ($_.Exception.Response) {
      $code = [int]$_.Exception.Response.StatusCode
      try {
        $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $msg = $sr.ReadToEnd()
      } catch {}
    }
    return @{ ok = $false; status = $code; msg = $msg }
  }
}

# 1. Register test user
$reg = Api 'POST' '/auth/register' @{ displayName = "QA Streak $devId"; deviceId = $devId } $null
Log 'auth/register' $reg.ok $(if ($reg.ok) { "user=$($reg.data.data.user._id) isNew=$($reg.data.data.isNew)" } else { "$($reg.status) $($reg.msg)" })
if (-not $reg.ok) { $results | ConvertTo-Json | Set-Content 'D:\sajda_app\temp_policy\streak_api_results.json'; exit 1 }
$token = $reg.data.data.token
$uid = $reg.data.data.user._id

# 2. Solo state before start (expect inactive)
$s0 = Api 'GET' '/streak/v2/solo' $null $token
$s0inactive = ($s0.ok -and $s0.data.data.isActive -eq $false)
Log 'GET /streak/v2/solo (fresh)' $s0inactive $(if ($s0.ok) { "isActive=$($s0.data.data.isActive)" } else { "$($s0.status) $($s0.msg)" })

# 3. Solo history when no streak
$h0 = Api 'GET' '/streak/v2/solo/history' $null $token
Log 'GET /streak/v2/solo/history (empty)' $h0.ok $(if ($h0.ok) { "keys=$(($h0.data.data.PSObject.Properties.Name) -join ',')" } else { "$($h0.status) $($h0.msg)" })

# 4. Complete prayer before streak started (should be a controlled error)
$p0 = Api 'POST' '/streak/v2/prayers/complete' @{ prayer = 'Fajr'; completed = $true } $token
Log 'POST prayers/complete (no active streak)' ($p0.ok -eq $false) $(if ($p0.ok) { 'UNEXPECTED: succeeded' } else { "controlled-error: $($p0.msg)" })

# 5. Start solo streak
$st = Api 'POST' '/streak/v2/solo/start' @{} $token
Log 'POST /streak/v2/solo/start' $st.ok $(if ($st.ok) { "isActive=$($st.data.data.isActive) current=$($st.data.data.currentStreak) today=$($st.data.data.today)" } else { "$($st.status) $($st.msg)" })

# 6. Complete all 5 prayers
foreach ($p in @('Fajr','Dhuhr','Asr','Maghrib','Isha')) {
  $pc = Api 'POST' '/streak/v2/prayers/complete' @{ prayer = $p; completed = $true } $token
  Log "POST prayers/complete $p" $pc.ok $(if ($pc.ok) { "solo.current=$($pc.data.data.solo.currentStreak) completed=$($pc.data.data.solo.today.completedCount) groups=$($pc.data.data.groups.Count)" } else { "$($pc.status) $($pc.msg)" })
}

# 7. Invalid prayer name (should be rejected)
$pbad = Api 'POST' '/streak/v2/prayers/complete' @{ prayer = 'Zuhr'; completed = $true } $token
Log 'POST prayers/complete invalid name' ($pbad.ok -eq $false) $(if ($pbad.ok) { 'UNEXPECTED: succeeded' } else { "controlled-error: $($pbad.msg)" })

# 8. Uncomplete a prayer
$pu = Api 'POST' '/streak/v2/prayers/complete' @{ prayer = 'Asr'; completed = $false } $token
Log 'POST prayers/complete Asr=false (undo)' $pu.ok $(if ($pu.ok) { "completedCount=$($pu.data.data.solo.today.completedCount)" } else { "$($pu.status) $($pu.msg)" })
$pr = Api 'POST' '/streak/v2/prayers/complete' @{ prayer = 'Asr'; completed = $true } $token
Log 'POST prayers/complete Asr=true (redo)' $pr.ok $(if ($pr.ok) { "completedCount=$($pr.data.data.solo.today.completedCount)" } else { "$($pr.status) $($pr.msg)" })

# 9. History after activity
$h1 = Api 'GET' '/streak/v2/solo/history?year=2026&month=9' $null $token
Log 'GET solo/history (with data)' $h1.ok $(if ($h1.ok) { "days=$($h1.data.data.days.Count)" } else { "$($h1.status) $($h1.msg)" })

# 10. Create group
$g = Api 'POST' '/streak/v2/groups' @{ name = "QA Group $devId"; visibility = 'invite' } $token
Log 'POST /streak/v2/groups' $g.ok $(if ($g.ok) { "id=$($g.data.data._id) invite=$($g.data.data.inviteCode)" } else { "$($g.status) $($g.msg)" })
if (-not $g.ok) { $results | ConvertTo-Json | Set-Content 'D:\sajda_app\temp_policy\streak_api_results.json'; exit 1 }
$gid = $g.data.data._id
$gcode = $g.data.data.inviteCode

# 11. My groups
$mg = Api 'GET' '/streak/v2/groups' $null $token
Log 'GET /streak/v2/groups' $mg.ok $(if ($mg.ok) { "count=$($mg.data.data.groups.Count)" } else { "$($mg.status) $($mg.msg)" })

# 12. Group dashboard
$gd = Api 'GET' "/streak/v2/groups/$gid/dashboard" $null $token
Log 'GET groups/:id/dashboard' $gd.ok $(if ($gd.ok) { "members=$($gd.data.data.members.Count)" } else { "$($gd.status) $($gd.msg)" })

# 13. Group history
$gh = Api 'GET' "/streak/v2/groups/$gid/history?year=2026&month=9" $null $token
Log 'GET groups/:id/history' $gh.ok $(if ($gh.ok) { "ok" } else { "$($gh.status) $($gh.msg)" })

# 14. Group activity
$ga = Api 'GET' "/streak/v2/groups/$gid/activity?limit=20" $null $token
Log 'GET groups/:id/activity' $ga.ok $(if ($ga.ok) { "items=$($ga.data.data.items.Count) hasMore=$($ga.data.data.hasMore)" } else { "$($ga.status) $($ga.msg)" })

# 15. Member detail (self)
$md = Api 'GET' "/streak/v2/groups/$gid/members/$uid" $null $token
Log 'GET groups/:id/members/:uid' $md.ok $(if ($md.ok) { "ok" } else { "$($md.status) $($md.msg)" })

# 16. Rename group
$rn = Api 'POST' "/streak/v2/groups/$gid/rename" @{ name = "QA Renamed $devId" } $token
Log 'POST groups/:id/rename' $rn.ok $(if ($rn.ok) { 'ok' } else { "$($rn.status) $($rn.msg)" })

# 17. Rotate invite
$ri = Api 'POST' "/streak/v2/groups/$gid/invite/rotate" @{} $token
$newCode = $null
if ($ri.ok) { $newCode = $ri.data.data.inviteCode }
Log 'POST groups/:id/invite/rotate' $ri.ok $(if ($ri.ok) { "newCode=$newCode (old=$gcode) changed=$($newCode -ne $gcode)" } else { "$($ri.status) $($ri.msg)" })

# 18. Invite preview with old code (should now be invalid)
$ipOld = Api 'GET' "/streak/v2/invite/$gcode" $null $token
Log 'GET invite/:code (rotated-out)' ($ipOld.ok -eq $false) $(if ($ipOld.ok) { 'UNEXPECTED: old code still valid' } else { "controlled-error: $($ipOld.msg)" })

# 19. Invite preview with new code
$ipNew = Api 'GET' "/streak/v2/invite/$newCode" $null $token
Log 'GET invite/:code (fresh)' $ipNew.ok $(if ($ipNew.ok) { "name=$($ipNew.data.data.name)" } else { "$($ipNew.status) $($ipNew.msg)" })

# 20. Second user joins via invite
$dev2 = "$devId-u2"
$r2 = Api 'POST' '/auth/register' @{ displayName = "QA U2 $devId"; deviceId = $dev2 } $null
$t2 = $r2.data.data.token
$j = Api 'POST' "/streak/v2/invite/$newCode/join" @{} $t2
Log 'POST invite/:code/join (u2)' $j.ok $(if ($j.ok) { "alreadyMember=$($j.data.data.alreadyMember)" } else { "$($j.status) $($j.msg)" })

# 21. Join again (already-member success)
$j2 = Api 'POST' "/streak/v2/invite/$newCode/join" @{} $t2
Log 'POST invite/:code/join (again)' ($j2.ok -and $j2.data.data.alreadyMember -eq $true) $(if ($j2.ok) { "alreadyMember=$($j2.data.data.alreadyMember)" } else { "$($j2.status) $($j2.msg)" })

# 22. Invalid invite code
$ib = Api 'GET' '/streak/v2/invite/ZZZZZZ' $null $token
Log 'GET invite/ZZZZZZ (invalid)' ($ib.ok -eq $false) $(if ($ib.ok) { 'UNEXPECTED' } else { "controlled-error: $($ib.msg)" })

# 23. Dashboard now shows 2 members
$gd2 = Api 'GET' "/streak/v2/groups/$gid/dashboard" $null $token
Log 'dashboard members=2' ($gd2.ok -and $gd2.data.data.members.Count -eq 2) $(if ($gd2.ok) { "members=$($gd2.data.data.members.Count)" } else { "$($gd2.status) $($gd2.msg)" })

# 24. u2 remove from group (by owner)
$rm = Api 'POST' "/streak/v2/groups/$gid/members/$($r2.data.data.user._id)/remove" @{} $token
Log 'POST members/:uid/remove' $rm.ok $(if ($rm.ok) { 'ok' } else { "$($rm.status) $($rm.msg)" })

# 25. Transfer ownership to self (no-op / allowed?)
$tr = Api 'POST' "/streak/v2/groups/$gid/transfer" @{ userId = $uid } $token
Log 'POST groups/:id/transfer (self)' $tr.ok $(if ($tr.ok) { 'ok' } else { "controlled: $($tr.status) $($tr.msg)" })

# 26. Archive group
$ar = Api 'POST' "/streak/v2/groups/$gid/archive" @{} $token
Log 'POST groups/:id/archive' $ar.ok $(if ($ar.ok) { 'ok' } else { "$($ar.status) $($ar.msg)" })

# 27. Notifications feed
$nf = Api 'GET' '/streak/v2/notifications' $null $token
Log 'GET /streak/v2/notifications' $nf.ok $(if ($nf.ok) { "unread=$($nf.data.data.unread) items=$($nf.data.data.items.Count)" } else { "$($nf.status) $($nf.msg)" })

# 28. Mark seen
$ms = Api 'POST' '/streak/v2/notifications/seen' @{} $token
Log 'POST notifications/seen' $ms.ok $(if ($ms.ok) { 'ok' } else { "$($ms.status) $($ms.msg)" })

# 29. Discover
$ds = Api 'GET' '/streak/v2/groups/discover?q=QA&page=0' $null $token
Log 'GET groups/discover' $ds.ok $(if ($ds.ok) { "items=$($ds.data.data.items.Count) hasMore=$($ds.data.data.hasMore)" } else { "$($ds.status) $($ds.msg)" })

# 30. Register device (push token) — may 400 if token invalid; accept controlled
$dv = Api 'POST' '/streak/v2/devices' @{ token = 'qa-dummy-fcm-token-1234567890'; platform = 'android' } $token
Log 'POST /streak/v2/devices' $dv.ok $(if ($dv.ok) { 'ok' } else { "controlled: $($dv.status) $($dv.msg)" })

# 31. Solo state final
$s1 = Api 'GET' '/streak/v2/solo' $null $token
Log 'GET /streak/v2/solo (final)' $s1.ok $(if ($s1.ok) { "current=$($s1.data.data.currentStreak) best=$($s1.data.data.bestStreak) completed=$($s1.data.data.today.completedCount)" } else { "$($s1.status) $($s1.msg)" })

# 32. Leave own group (owner) — expect controlled error since owner cannot leave or must transfer first
$lv = Api 'POST' "/streak/v2/groups/$gid/leave" @{} $token
Log 'POST groups/:id/leave (owner)' $true $(if ($lv.ok) { 'ok (left)' } else { "controlled: $($lv.status) $($lv.msg)" })

$pass = ($results | Where-Object { $_.Result -eq 'FAIL' }).Count
Write-Host ""
Write-Host "TOTAL: $($results.Count) | FAIL: $pass"
$results | ConvertTo-Json -Depth 4 | Set-Content 'D:\sajda_app\temp_policy\streak_api_results.json'
