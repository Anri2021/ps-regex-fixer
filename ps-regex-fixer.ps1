<#
    Fix-CorruptedScript.ps1
    מתקן ארטיפקטים של LaTeX ומפריד שורות/משתנים שנדבקו בסקריפט PowerShell.
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$InputPath,

    [Parameter(Position = 1)]
    [string]$OutputPath = ""
)

function Get-FileEncoding([string]$path) {
     $bytes = [System.IO.File]::ReadAllBytes( $path)

    if ( $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and  $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8
    }

    try {
         $utf8Strict = [System.Text.UTF8Encoding]::new( $false, $true)
         $utf8Strict.GetString( $bytes) | Out-Null
        return [System.Text.Encoding]::UTF8
    } catch {
        return [System.Text.Encoding]::GetEncoding("windows-1255")
    }
}

# פונקציית עזר לפענוח מחרוזות Base64 בזמן ריצה
function Decode-B64([string]$b64) {
    [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64))
}

# אימות קיום קובץ הקלט
if (-not (Test-Path $InputPath)) {
    Write-Host "[-] File '$InputPath' not found. Verify path and retry." -ForegroundColor Red
    return
}

# קביעת נתיב יעד אוטומטי עם סיומת .fix.ps1 במידה ולא סופק
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = [System.IO.Path]::ChangeExtension( $InputPath, 'fix.ps1')
}

# 1. קריאת תוכן הקובץ המקורי (שימוש ב-ProviderPath למניעת שגיאות ניתוב)
$resolvedPath = (Resolve-Path $InputPath).ProviderPath
$fileEnc = Get-FileEncoding $resolvedPath
$raw = [System.IO.File]::ReadAllText( $resolvedPath, $fileEnc)

# 2. אתחול משתנה עבודה
$clean = $raw

# 3. מנוע החלפות ותיקונים מבוסס Base64
$rules = @(
    # --- שחזור ארטיפקטים של LaTeX ---
    # \vert{} -> |
    @{ P = 'XFx2ZXJ0XHtcfQ=='; R = 'fA==' }

    # שחזור משתנים: \(var או\)var -> $var (תומך גם ב-_ ובמאפיינים)
    @{ P = 'KD86XFxbKCldKStcJD8oW2EtekEtWl9dW2EtekEtWjAtOV9dKik='; R = 'JCQkMQ==' }

    # מחיקת שאריות ארטיפקטים של LaTeX שלא שויכו למשתנה
    @{ P = 'XFxcKQ=='; R = '' }
    @{ P = 'XFxcKA=='; R = '' }

    # תיקון ארטיפקט מודולו של LaTeX: \% -> %
    @{ P = 'XFwl'; R = 'JQ==' }

    # --- הפרדת פקודות וערכים שנדבקו ---
    # תיקון לולאות foreach: foreach (\(var |\)col) -> foreach (\(var in\)col)
    @{ P = 'KFxiZm9yZWFjaFxzKlwoXHMqXCRcdyspXHMqXHxccypcJD8='; R = 'JDEgaW4gJCQ=' }

    # ) \(var -> );\)var
    @{ P = 'KFwpKShcJCk='; R = 'JDE7ICQy' }

    # } \(var -> };\)var
    @{ P = 'KFx9KShcJCk='; R = 'JDE7ICQy' }

    # [] \(var -> []\)var (פותר הדבקות כגון New-Object byte[] $length)
    @{ P = 'KFxbXF0pKFwkKQ=='; R = 'JDEgJDI=' }

    # \(var++\)var -> \(var++;\)var (מזהה משתנה לפני ה-++)
    @{ P = 'KFwkXHcrXCtcKykoXCQp'; R = 'JDE7ICQy' }

    # 255 \(var / 0x07FF\)var -> ...; $var
    @{ P = 'KFxiKD86MHhbMC05YS1mQS1GXSt8XGQrKSkoXCQp'; R = 'JDE7ICQy' }

    # break / continue \(var -> break/continue;\)var
    @{ P = 'KFxiKD86YnJlYWt8Y29udGludWUpKShcJCk='; R = 'JDE7ICQy' }

    # return \(var או return ,\)arr -> return $var (רווח בלבד, מונע ניתוק הערך המוחזר!)
    @{ P = 'KFxicmV0dXJuKShbXCQsXSk='; R = 'JDEgJDI=' }

    # Show-HexDump \(ref\)ctxStart (הפרדת ארגומנטים לפונקציה ברווח)
    @{ P = 'KFwkcmVmKShcJGN0eFN0YXJ0KQ=='; R = 'JDEgJDI=' }

    # משתנה צמוד למשתנה: \(tmp\)p19 -> \(tmp;\)p19
    @{ P = 'KFwkW2EtekEtWjAtOV9dKykoXCRbYS16QS1aX10p'; R = 'JDE7ICQy' }

    # -op \(var -> -op\)var (מפריד דגלים ואופרטורים שנדבקו: -ne, -eq, -f, -and, -length)
    @{ P = 'KC1bYS16QS1aXSspKFwkKQ=='; R = 'JDEgJDI=' }

    # in \(var -> in\)var
    @{ P = 'KFxiaW4pKFwkKQ=='; R = 'JDEgJDI=' }

    # Cmdlet-Name \(var -> Cmdlet-Name\)var
    @{ P = 'KFxiW2EtekEtWl0rLVthLXpBLVowLTldKykoXCQp'; R = 'JDEgJDI=' }

    # [type]; \(var -> [type]\)var (ניקוי נקודה-פסיק שגויה לאחר Type Cast)
    @{ P = 'XFsoW2EtekEtWjAtOV9cW1xdXSspXF1ccyo7XHMqKFwkKQ=='; R = 'WyQxXSAkMg==' }

    # הפרדת אינדקס מערך שנדבק למשתנה: \(arr[idx]\)var -> \(arr[idx];\)var
    @{ P = 'KFwkXHcrXFtbXlxdXHJcbl0rXF0pKFwkXHcrKQ=='; R = 'JDE7ICQy' }

    # הפרדת צבע פלט שנדבק למשתנה: -ForegroundColor Color \(var -> ...Color;\)var
    @{ P = 'KC1Gb3JlZ3JvdW5kQ29sb3JccytbYS16QS1aXSspKFwkKQ=='; R = 'JDE7ICQy' }

    # הפרדת אופרטורים חשבוניים שנדבקו למשתנה: +\(var / *\)var -> + $var
    @{ P = 'KFtcK1wqXC9dKShcJCk='; R = 'JDEgJDI=' }
)

foreach ($r in $rules) {
    $pattern = Decode-B64 $r.P
    $replacement = if ([string]::IsNullOrEmpty( $r.R)) { '' } else { Decode-B64 $r.R }
    $clean = [regex]::Replace( $clean, $pattern, $replacement)
}

# 4. שמירת התוצאה לקובץ היעד (מתבצעת תמיד לפני בדיקת ה-AST)
$targetPath = [System.IO.Path]::GetFullPath( $OutputPath)
[System.IO.File]::WriteAllText($targetPath, $clean, [System.Text.Encoding]::UTF8)
Write-Host "[+] Fixed script saved to: $OutputPath" -ForegroundColor Green

# 5. בדיקת תקינות תחבירית (AST Parser) - מוגנת מפני קריסות פלט
try {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseInput($clean, [ref] $tokens, [ref]$errors) | Out-Null

    if ($null -eq $errors -or $errors.Count -eq 0) {
        Write-Host "[V] Syntax check passed! Code is valid and ready." -ForegroundColor Cyan
    } else {
        Write-Host ("[-] Found {0} syntax errors requiring review:" -f $errors.Count) -ForegroundColor Yellow
        foreach ($err in $errors) {
            Write-Host ("  -> Line {0}: {1}" -f $err.Extent.StartLineNumber,$err.Message) -ForegroundColor Red
        }
    }
} catch {
    Write-Host "[-] AST check failed, but output file was saved." -ForegroundColor Yellow
}
