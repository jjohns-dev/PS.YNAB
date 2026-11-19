function Update-YnabSessionToken {
    <#
    .SYNOPSIS
        Obtains a new OAuth token pair for the session and hands the refresh token to the caller.
    .DESCRIPTION
        Sends a token request for the OAuth session in $script:YnabOAuth: a refresh_token grant by default, or the
        grant given with -Grant, such as Connect-Ynab's authorization_code exchange. The client ID and secret are
        added from the session.

        On success it replaces the session's access token, refresh token and expiry, disposes the old tokens, and
        then calls the session's -OnTokenRefresh scriptblock with a separate copy of the new refresh token and the
        access token's expiry, before returning, so no further request is sent first (ADR-0007). If the scriptblock
        throws, the session keeps the new tokens and a non-terminating YnabOAuthTokenRefreshCallbackFailed error is
        written.

        If the token request fails, the session is ended with Disconnect-Ynab and YnabOAuthRefreshFailed is raised.
    .PARAMETER Grant
        Form fields for a grant other than refresh_token, without client_id and client_secret.
    .INPUTS
        None.
    .OUTPUTS
        None.
    .EXAMPLE
        PS C:\> Update-YnabSessionToken
        Redeems the session's refresh token for a new token pair.
    .NOTES
        Status: Beta
        https://api.ynab.com/#oauth-applications
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Changes only the in-memory session, like Connect-Ynab; -WhatIf would skip a needed refresh.')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'YNAB returns tokens as plain JSON strings; they are wrapped in SecureString immediately.')]
    [CmdletBinding()]
    [OutputType([System.Void])]
    Param(
        [Parameter(HelpMessage = 'Form fields for a grant other than refresh_token')]
        [System.Collections.IDictionary] $Grant
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        $oauth = $script:YnabOAuth
        if (-not $oauth) {
            $errorParams = @{
                Message  = 'There is no OAuth session to refresh. Run Connect-Ynab with -ClientId first.'
                ErrorId  = 'YnabOAuthNoSession'
                Category = 'ConnectionError'
            }
            Write-Error @errorParams -ErrorAction Stop
        }

        # PLAIN-TEXT COPIES EXIST ONLY FOR THIS REQUEST; Clean REMOVES THEM
        $isRefresh = -not $PSBoundParameters.ContainsKey('Grant')
        $form = @{
            client_id     = $oauth.ClientId
            client_secret = ConvertFrom-SecureString -SecureString $oauth.ClientSecret -AsPlainText
        }
        if ($isRefresh) {
            $form['grant_type'] = 'refresh_token'
            $form['refresh_token'] = ConvertFrom-SecureString -SecureString $oauth.RefreshToken -AsPlainText
        }
        else {
            foreach ($key in $Grant.Keys) {
                $form[$key] = $Grant[$key]
            }
        }

        try {
            $response = Invoke-YnabRequest -TokenGrant $form
        }
        catch {
            $reason = $PSItem.ToString()
            Disconnect-Ynab
            $message = if ($isRefresh) {
                ('The OAuth refresh token is no longer valid ({0}). The session has ended; ' +
                    'authorize again with Connect-Ynab -ClientId and -ClientSecret.') -f $reason
            }
            else {
                ('The OAuth token request failed ({0}). ' +
                    'Authorize again with Connect-Ynab -ClientId and -ClientSecret.') -f $reason
            }
            $errorParams = @{
                Message   = $message
                Exception = $PSItem.Exception
                ErrorId   = 'YnabOAuthRefreshFailed'
                Category  = 'AuthenticationError'
            }
            Write-Error @errorParams -ErrorAction Stop
        }

        # REPLACE THE PAIR; A REFRESH HAS ALREADY REVOKED THE OLD ONE ON YNAB'S SIDE
        $newAccess = ConvertTo-SecureString -String $response.access_token -AsPlainText -Force
        $newAccess.MakeReadOnly()
        $newRefresh = ConvertTo-SecureString -String $response.refresh_token -AsPlainText -Force
        $newRefresh.MakeReadOnly()
        $oldAccess = $script:YnabToken
        $oldRefresh = $oauth.RefreshToken
        $script:YnabToken = $newAccess
        $oauth.RefreshToken = $newRefresh
        $oauth.ExpiresAt = (Get-Date).ToUniversalTime().AddSeconds([System.Int32] $response.expires_in)
        if ($oldAccess) {
            $oldAccess.Dispose()
        }
        if ($oldRefresh) {
            $oldRefresh.Dispose()
        }
        $obtainedMessage = 'Obtained a new OAuth token pair; the access token expires at {0:o}.' -f $oauth.ExpiresAt
        Write-Verbose -Message $obtainedMessage

        # HAND THE NEW REFRESH TOKEN TO THE CALLER BEFORE ANY FURTHER REQUEST (ADR-0007)
        if ($oauth.OnTokenRefresh) {
            $handoff = [PSCustomObject] @{
                RefreshToken         = $newRefresh.Copy()
                AccessTokenExpiresAt = $oauth.ExpiresAt
            }
            try {
                $null = & $oauth.OnTokenRefresh $handoff
            }
            catch {
                $errorParams = @{
                    Message   = ('The -OnTokenRefresh scriptblock failed, so the new refresh token may not have been ' +
                        'saved; any previously saved refresh token is now revoked. The session keeps working. ' +
                        'Error: {0}') -f $PSItem.Exception.Message
                    Exception = $PSItem.Exception
                    ErrorId   = 'YnabOAuthTokenRefreshCallbackFailed'
                    Category  = 'WriteError'
                }
                Write-Error @errorParams
            }
        }
    }
    Clean {
        Remove-Variable -Name 'form', 'response', 'Grant' -Force -ErrorAction Ignore
    }
}
