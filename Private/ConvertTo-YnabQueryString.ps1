function ConvertTo-YnabQueryString {
    <#
    .SYNOPSIS
        Builds a URI query string from a dictionary of query parameters.
    .DESCRIPTION
        Returns key=value pairs joined with &, URI-escaped, in sorted key order, leaving out entries whose value is
        null. Returns an empty string when nothing is left. Invoke-YnabRequest uses it to build request URIs and
        Invoke-YnabCachedRequest to build cache keys, so both always agree.
    .PARAMETER Query
        Query parameters.
    .INPUTS
        None.
    .OUTPUTS
        System.String.
    .EXAMPLE
        PS C:\> ConvertTo-YnabQueryString -Query @{ type = 'unapproved'; since_date = '2026-11-01' }
        Returns since_date=2026-11-01&type=unapproved.
    .NOTES
        Status: Beta
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    Param(
        [Parameter(HelpMessage = 'Query parameters')]
        [AllowNull()]
        [System.Collections.IDictionary] $Query
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        if (-not $Query) {
            return ''
        }
        $queryPairs = foreach ($key in ($Query.Keys | Sort-Object)) {
            if ($null -ne $Query[$key]) {
                $escapedKey = [System.Uri]::EscapeDataString([System.String] $key)
                $escapedValue = [System.Uri]::EscapeDataString([System.String] $Query[$key])
                '{0}={1}' -f $escapedKey, $escapedValue
            }
        }
        @($queryPairs) -join '&'
    }
}
