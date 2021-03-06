function Get-MailboxForwardAndRedirectRules {
    <#
    .SYNOPSIS
    Retrieves a list of mailbox rules which forward or redirect email elsewhere.
    .DESCRIPTION
    Retrieves a list of mailbox rules which forward or redirect email elsewhere.
    .PARAMETER MailboxNames
    Array of mailbox names in string format.    
    .PARAMETER MailboxObject
    One or more mailbox objects.
    .LINK
    http://www.the-little-things.net
    .NOTES
    Last edit   :   11/04/2014
    Version     :   
    1.1.0 11/04/2014
    - Minor structual changes and input parameter updates
    1.0.0 10/04/2014
    - Initial release
    Author      :   Zachary Loeber
    Original Author: https://gallery.technet.microsoft.com/PowerShell-Script-To-Get-0f1bb6a7/

    .EXAMPLE
    Get-MailboxForwardAndRedirectRules -MailboxName "Test User1"

    Description
    -----------
    TBD
    #>
    [CmdLetBinding(DefaultParameterSetName='AsMailbox')]
    param(
        [Parameter(ParameterSetName='AsStringArray', Mandatory=$True, ValueFromPipeline=$True, Position=0, HelpMessage="Enter an Exchange mailbox name")]
        [string[]]$MailboxNames,
        [Parameter(ParameterSetName='AsMailbox', Mandatory=$True, ValueFromPipeline=$True, Position=0, HelpMessage="Enter an Exchange mailbox name")]
        $MailboxObject
    )
    begin {
        Write-Verbose "$($MyInvocation.MyCommand): Begin"
        $Mailboxes = @()
    }
    process {
        switch ($PSCmdlet.ParameterSetName) {
            'AsStringArray' {
                try {
                    $Mailboxes = @($MailboxNames | Foreach {Get-Mailbox $_ -erroraction Stop})
                }
                catch {
                    Write-Warning = "$($MyInvocation.MyCommand): $_.Exception.Message"
                }
            }
            'AsMailbox' {
               $Mailboxes = @($MailboxObject)
            }
        }

        foreach ($Mailbox in $Mailboxes) {
            Write-Verbose "$($MyInvocation.MyCommand): Checking $($Mailbox.Name)"
            $rules = Get-InboxRule -mailbox $Mailbox.DistinguishedName -ErrorAction:SilentlyContinue | 
                     Where {($_.forwardto -ne $null) -or 
                            ($_.redirectto -ne $null) -or 
                            ($_.ForwardAsAttachmentTo -ne $null) -and 
                            ($_.ForwardTo -notmatch "EX:/") -and 
                            ($_.RedirectTo -notmatch "EX:/") -and 
                            ($_.ForwardAsAttachmentTo -notmatch "EX:/")} 
            if ($rules.Count -gt 0)
            {
                $rules | 
                    Select @{n="Mailbox";e={($Mailbox.Name)}}, `
                           @{n="Rule";e={$_.name}},Enabled, `
                           @{Name="ForwardTo";Expression={[string]::join(";",($_.forwardTo))}}, `
                           @{Name="RedirectTo";Expression={[string]::join(";",($_.redirectTo))}}, `
                           @{Name="ForwardAsAttachmentTo";Expression={[string]::join(";",($_.ForwardAsAttachmentTo))}} 
            }
        }
    }
    end {
        Write-Verbose "$($MyInvocation.MyCommand): End"
    }
}