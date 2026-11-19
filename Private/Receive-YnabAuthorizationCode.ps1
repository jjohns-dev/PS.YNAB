function Receive-YnabAuthorizationCode {
    <#
    .SYNOPSIS
        Opens YNAB's authorize page in the browser and returns the authorization code.
    .DESCRIPTION
        Loopback (the default): checks that the redirect URI is http on localhost, 127.0.0.1 or [::1], starts an
        HttpListener on that host and port before opening the browser, and waits up to -TimeoutSeconds for a request
        on the redirect path. Requests on other paths are answered 404 and ignored. The redirect is answered with a
        short page saying the tab can be closed, and the listener is stopped on every path out of the function.

        Out-of-band (-OutOfBand): opens the browser and reads the code that YNAB displays with
        Read-Host -AsSecureString. There is no redirect to carry the state; PKCE protects the exchange instead.

        Either way the authorize URL is also written to the information stream, so it can be copied when no browser
        opens. A redirect carrying an error, or a state other than the one sent, raises YnabOAuthAuthorizationFailed.
    .PARAMETER AuthorizeUri
        URL of YNAB's authorize page, from New-YnabOAuthRequest.
    .PARAMETER RedirectUri
        Loopback redirect URI registered for the application, such as http://localhost:8765/callback.
    .PARAMETER State
        State sent in the authorize URL; the redirect must return the same value.
    .PARAMETER TimeoutSeconds
        How long to wait for the redirect.
    .PARAMETER OutOfBand
        Read the code from the console instead of a loopback redirect.
    .INPUTS
        None.
    .OUTPUTS
        System.Security.SecureString. The authorization code.
    .EXAMPLE
        PS C:\> $code = Receive-YnabAuthorizationCode -AuthorizeUri $uri -RedirectUri $redirect -State $state
        Opens the browser and waits for YNAB to redirect back with the code.
    .EXAMPLE
        PS C:\> $code = Receive-YnabAuthorizationCode -AuthorizeUri $uri -OutOfBand
        Opens the browser and prompts for the code YNAB displays.
    .NOTES
        Status: Beta
        https://api.ynab.com/#oauth-applications
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'The code arrives in a URL query string; it is wrapped in SecureString immediately.')]
    [CmdletBinding(DefaultParameterSetName = '_loopback')]
    [OutputType([System.Security.SecureString])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'URL of the authorize page')]
        [ValidateNotNullOrEmpty()]
        [System.String] $AuthorizeUri,

        [Parameter(Mandatory, ParameterSetName = '_loopback', HelpMessage = 'Loopback redirect URI')]
        [ValidateNotNullOrEmpty()]
        [System.String] $RedirectUri,

        [Parameter(Mandatory, ParameterSetName = '_loopback', HelpMessage = 'State sent in the authorize URL')]
        [ValidateNotNullOrEmpty()]
        [System.String] $State,

        [Parameter(ParameterSetName = '_loopback', HelpMessage = 'Seconds to wait for the redirect')]
        [ValidateRange(1, 3600)]
        [System.Int32] $TimeoutSeconds = 300,

        [Parameter(Mandatory, ParameterSetName = '_outOfBand', HelpMessage = 'Read the code from the console')]
        [System.Management.Automation.SwitchParameter] $OutOfBand
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)

        $openBrowser = {
            param ([System.String] $Uri)
            $informationParams = @{
                MessageData       = 'If no browser opens, open this URL to authorize PS.YNAB: {0}' -f $Uri
                InformationAction = 'Continue'
            }
            Write-Information @informationParams
            try {
                Start-Process -FilePath $Uri -ErrorAction Stop
            }
            catch {
                Write-Warning -Message ('Could not open a browser: {0}' -f $PSItem.Exception.Message)
            }
        }
        $sendPage = {
            param ($Response, [System.Int32] $StatusCode, [System.String] $Text)
            $bytes = [System.Text.Encoding]::UTF8.GetBytes(
                ('<!doctype html><title>PS.YNAB</title><p>{0}</p>' -f [System.Net.WebUtility]::HtmlEncode($Text))
            )
            $Response.StatusCode = $StatusCode
            $Response.ContentType = 'text/html; charset=utf-8'
            $Response.ContentLength64 = $bytes.Length
            $Response.OutputStream.Write($bytes, 0, $bytes.Length)
            $Response.Close()
        }
    }
    Process {
        if ($OutOfBand) {
            & $openBrowser $AuthorizeUri
            $code = Read-Host -Prompt 'Paste the authorization code YNAB shows' -AsSecureString
            if ($code.Length -eq 0) {
                $errorParams = @{
                    Message  = 'No authorization code was entered.'
                    ErrorId  = 'YnabOAuthAuthorizationFailed'
                    Category = 'AuthenticationError'
                }
                Write-Error @errorParams -ErrorAction Stop
            }
            return $code
        }

        # ONLY A PLAIN-HTTP LOOPBACK REDIRECT CAN BE RECEIVED HERE
        $redirect = $null
        $isLoopback = [System.Uri]::TryCreate($RedirectUri, [System.UriKind]::Absolute, [ref] $redirect) -and
            $redirect.Scheme -eq 'http' -and $redirect.Host -in 'localhost', '127.0.0.1', '[::1]'
        if (-not $isLoopback) {
            $errorParams = @{
                Message      = ('The redirect URI {0} is not an http URI on localhost, 127.0.0.1 or [::1]. ' +
                    'Use a loopback redirect URI registered for the application, or -OutOfBand.') -f $RedirectUri
                ErrorId      = 'YnabOAuthRedirectNotLoopback'
                Category     = 'InvalidArgument'
                TargetObject = $RedirectUri
            }
            Write-Error @errorParams -ErrorAction Stop
        }

        # START LISTENING BEFORE THE BROWSER OPENS, SO A PORT IN USE FAILS BEFORE THE USER AUTHORIZES (AC-17)
        $listener = [System.Net.HttpListener]::new()
        try {
            $listener.Prefixes.Add(('http://{0}:{1}/' -f $redirect.Host, $redirect.Port))
            try {
                $listener.Start()
            }
            catch {
                $errorParams = @{
                    Message      = ('Could not listen for the redirect on {0}: {1} If the port is in use, register ' +
                        'another loopback redirect URI for the application and pass it with -RedirectUri.') -f
                    $RedirectUri, $PSItem.Exception.Message
                    Exception    = $PSItem.Exception
                    ErrorId      = 'YnabOAuthListenerFailed'
                    Category     = 'ResourceUnavailable'
                    TargetObject = $RedirectUri
                }
                Write-Error @errorParams -ErrorAction Stop
            }
            Write-Verbose -Message ('Listening for the redirect on {0}.' -f $RedirectUri)

            & $openBrowser $AuthorizeUri

            # WAIT IN SHORT SLICES SO CTRL+C CAN INTERRUPT; IGNORE REQUESTS ON OTHER PATHS, SUCH AS /favicon.ico
            $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
            $query = $null
            while (-not $query) {
                $pending = $listener.GetContextAsync()
                while (-not $pending.Wait(250)) {
                    if ((Get-Date) -ge $deadline) {
                        $errorParams = @{
                            Message      = ('No authorization arrived at {0} within {1} seconds. Run Connect-Ynab ' +
                                'again, or raise -TimeoutSeconds.') -f $RedirectUri, $TimeoutSeconds
                            ErrorId      = 'YnabOAuthTimeout'
                            Category     = 'OperationTimeout'
                            TargetObject = $RedirectUri
                        }
                        Write-Error @errorParams -ErrorAction Stop
                    }
                }
                $context = $pending.Result
                if ($context.Request.Url.AbsolutePath -ne $redirect.AbsolutePath) {
                    & $sendPage $context.Response 404 'Not found.'
                    continue
                }
                $query = $context.Request.QueryString
            }

            # REJECT AN ERROR OR A FOREIGN STATE BEFORE ANY TOKEN REQUEST (AC-4)
            $failure = if ($query['error']) {
                'YNAB returned {0}: {1}' -f $query['error'], $query['error_description']
            }
            elseif ($query['state'] -cne $State) {
                'The state in the redirect does not match the one sent, so the redirect was not started by this command'
            }
            elseif (-not $query['code']) {
                'The redirect carried no authorization code'
            }
            if ($failure) {
                & $sendPage $context.Response 400 'Authorization failed. Return to PowerShell for details.'
                $errorParams = @{
                    Message      = '{0}. Run Connect-Ynab again to authorize.' -f $failure.TrimEnd('.')
                    ErrorId      = 'YnabOAuthAuthorizationFailed'
                    Category     = 'AuthenticationError'
                    TargetObject = $RedirectUri
                }
                Write-Error @errorParams -ErrorAction Stop
            }

            & $sendPage $context.Response 200 'PS.YNAB is authorized. You can close this tab and return to PowerShell.'
            ConvertTo-SecureString -String $query['code'] -AsPlainText -Force
        }
        finally {
            $listener.Close()
        }
    }
    Clean {
        Remove-Variable -Name 'query', 'context', 'code' -Force -ErrorAction Ignore
    }
}
