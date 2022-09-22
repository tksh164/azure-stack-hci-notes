param (
    [Parameter(Mandatory = $true)]
    [string] $LogFilePath
)

$fieldLine = ''
$entry = @{}

Get-Content -LiteralPath $LogFilePath -Encoding unicode |
    ForEach-Object -Process {
        $line = $_
        if ($line.StartsWith(' ')) {
            # The line is a continuing field line.
            $fieldLine += $line.Trim()
        }
        else {
            if ($fieldLine -ne '') {
                # A field line ends.
                $fieldName, $fieldValue = $fieldLine.Split(':', 2, [StringSplitOptions]::None)
                $fieldName = $fieldName.Trim()
                $fieldValue = $fieldValue.Trim()
                $entry[$fieldName] = $fieldValue
            }

            if ($line.Trim() -eq '') {
                # All fields in an entry were captured.
                if ($entry.Count -ne 0) { [PSCustomObject] $entry }
                $entry = @{}
            }
            else {
                # A new field line starts.
                $fieldLine = $line
            }
        }
    } | ConvertTo-Csv -Delimiter "`t" -NoTypeInformation
