Get-Clipboard | ForEach-Object { $_ -replace '__DLR__','$' -replace '__LT__','<' -replace '__GT__','>' -replace '__AMP__','&' } | Set-Clipboard
