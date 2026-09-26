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

# פונקציית עזר לפענוח מחרוזות Base64 בזמן ריצה
function Decode-B64([string]$b64) {
    [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64))
}

# אימות קיום קובץ הקלט
if (-not (Test-Path $InputPath)) {
    Write-Host "[-] הקובץ '$InputPath' לא נמצא. ודא את הנתיב והרם שוב." -ForegroundColor Red
    return
}

# קביעת נתיב יעד אוטומטי עם סיומת .fix.ps1 במידה ולא סופק
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = [System.IO.Path]::ChangeExtension($InputPath, 'fix.ps1')
}

# 1. קריאת תוכן הקובץ המקורי
$raw = [System.IO.File]::ReadAllText((Resolve-Path $InputPath), [System.Text.Encoding]::UTF8)

# 2. אתחול משתנה עבודה
$clean = $raw

# 3. מנוע החלפות ותיקונים מבוסס Base64
$rules = @(
    # --- שחזור ארטיפקטים של LaTeX ---
    # \vert{} -> |
    @{ P = 'XFx2ZXJ0XHtcfQ=='; R = 'fA==' }

    # שחזור משתנים: \(var או\)var או \(\(var -> \(var (תומך גם ב-\)_ ובמשתנים בוליאניים)
    @{ P = 'KD86XFxbKCldKStcJD8oW2EtekEtWl9dW2EtekEtWjAtOV9dKik='; R = 'JCQkMQ==' }

    # מחיקת שאריות ארטיפקטים של LaTeX שלא שויכו למשתנה
    @{ P = 'XFxcKQ=='; R = '' }
    @{ P = 'XFxcKA=='; R = '' }

    # --- הפרדת פקודות וערכים שנדבקו ---
    # ) \(var -> );\)var
    @{ P = 'KFwpKShcJCk='; R = 'JDE7ICQy' }

    # } \(var -> };\)var
    @{ P = 'KFx9KShcJCk='; R = 'JDE7ICQy' }

    # [] \(var -> []\)var (פותר הדבקות כגון New-Object byte[] $length)
    @{ P = 'KFxbXF0pKFwkKQ=='; R = 'JDEgJDI=' }

    # ++ \(var -> ++;\)var (פותר הדבקות כגון \(namesOffset++;\)name)
    @{ P = 'KFwrXCspKFwkKQ=='; R = 'JDE7ICQy' }

    # 255 \(var / 0x07FF\)var -> ...; $var
    @{ P = 'KFxiKD86MHhbMC05YS1mQS1GXSt8XGQrKSkoXCQp'; R = 'JDE7ICQy' }

    # break/continue/return \(var -> ...;\)var
    @{ P = 'KFxiKD86YnJlYWt8Y29udGludWV8cmV0dXJuKSkoXCQp'; R = 'JDE7ICQy' }

    # Show-HexDump \(ref\)ctxStart
    @{ P = 'KFwkcmVmKShcJGN0eFN0YXJ0KQ=='; R = 'JDEgJDI=' }

    # משתנה צמוד למשתנה: \(tmp\)p19 -> \(tmp;\)p19
    @{ P = 'KFwkW2EtekEtWjAtOV9dKykoXCRbYS16QS1aX10p'; R = 'JDE7ICQy' }

    # -op \(var -> -op\)var (מפריד אופרטורים ודגלים שנדבקו: -ne, -eq, -f, -and, -or, -length)
    @{ P = 'KC1bYS16QS1aXSspKFwkKQ=='; R = 'JDEgJDI=' }

    # in \(var -> in\)var
    @{ P = 'KFxiaW4pKFwkKQ=='; R = 'JDEgJDI=' }

    # Cmdlet-Name \(var -> Cmdlet-Name\)var
    @{ P = 'KFxiW2EtekEtWl0rLVthLXpBLVowLTldKykoXCQp'; R = 'JDEgJDI=' }

    # [type]; \(var -> [type]\)var
    @{ P = 'XFsoW2EtekEtWjAtOV9cW1xdXSspXF1ccyo7XHMqKFwkKQ=='; R = 'WyQxXSAkMg==' }
)

foreach ($r in $rules) {
    $pattern = Decode-B64 $r.P
    $replacement = if ([string]::IsNullOrEmpty($r.R)) { '' } else { Decode-B64 $r.R }
    $clean = [regex]::Replace($clean, $pattern, $replacement)
}

# 4. שמירת התוצאה לקובץ היעד
$targetPath = [System.IO.Path]::GetFullPath($OutputPath)
[System.IO.File]::WriteAllText($targetPath, $clean, [System.Text.Encoding]::UTF8)
Write-Host "[+] הקובץ המתוקן נשמר בהצלחה בנתיב: $OutputPath" -ForegroundColor Green

# 5. בדיקת תקינות תחבירית (AST Parser)
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseInput($clean, [ref]$tokens, [ref]$errors) | Out-Null

if ($errors.Count -eq 0) {
    Write-Host "[V] בדיקת תחביר עברה בהצלחה! הקוד תקין ומוכן להרצה." -ForegroundColor Cyan
} else {
    Write-Host "[-] אותרו $($errors.Count) שגיאות תחביר שדורשות בדיקה ידנית:" -ForegroundColor Yellow
    foreach ($err in $errors) {
        Write-Host ("  -> שורה {0}: {1}" -f $err.Extent.StartLineNumber, $err.Message) -ForegroundColor Red
    }
}
