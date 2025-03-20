# SharePoint-Permissions-Audit.ps1
# A script to audit SharePoint folder permissions with flexible depth options
# Author: Ruben Quispe
# GitHub: https://github.com/yourusername/SharePoint-Permissions-Audit

param(
    [string]$TenantName = "", # Your tenant name (e.g., "contoso")
    [string]$SiteUrl = "", # Full site URL (e.g., "https://contoso.sharepoint.com/sites/yoursite")
    [string]$ClientID = "", # App registration client ID
    [string]$CertificatePath = "", # Path to PFX certificate file
    [string]$LibraryName = "Documents", # Document library name to audit
    [string]$CsvPath = "$($env:USERPROFILE)\Desktop\SharePoint_Permissions_Audit.csv", # Output file path
    [int]$Option = 0 # 0=prompt user, 1=top folders only, 2=all folders
)

# Function to show banner
function Show-Banner {
    Write-Host "SharePoint Folder Permissions Audit Tool" -ForegroundColor Cyan
    Write-Host "=======================================" -ForegroundColor Cyan
    Write-Host "This tool audits permissions on SharePoint folders" -ForegroundColor Cyan
    Write-Host ""
}

# Function to prompt for parameters if not provided
function Get-Parameters {
    Show-Banner
    
    if ([string]::IsNullOrEmpty($TenantName)) {
        $TenantName = Read-Host "Enter your tenant name (e.g., 'contoso' for contoso.sharepoint.com)"
    }
    
    if ([string]::IsNullOrEmpty($SiteUrl)) {
        $SiteUrl = Read-Host "Enter the full SharePoint site URL (e.g., 'https://contoso.sharepoint.com/sites/yoursite')"
    }
    
    if ([string]::IsNullOrEmpty($ClientID)) {
        $ClientID = Read-Host "Enter the App Registration Client ID"
    }
    
    if ([string]::IsNullOrEmpty($CertificatePath)) {
        $CertificatePath = Read-Host "Enter the path to the PFX certificate file"
    }
    
    if ($Option -eq 0) {
        Write-Host ""
        Write-Host "Audit Options:" -ForegroundColor Cyan
        Write-Host "1: Audit only top-level folders under the document library" -ForegroundColor Green
        Write-Host "2: Audit ALL folders and subfolders (may take long time)" -ForegroundColor Yellow
        $choice = Read-Host "Enter your choice (1 or 2)"
        
        if ($choice -eq "2") {
            $Option = 2
        } else {
            $Option = 1
        }
    }
    
    # Return all parameters
    return @{
        TenantName = $TenantName
        SiteUrl = $SiteUrl
        ClientID = $ClientID
        CertificatePath = $CertificatePath
        Option = $Option
    }
}

# Main script execution
try {
    # Get parameters
    $params = Get-Parameters
    $TenantName = $params.TenantName
    $SiteUrl = $params.SiteUrl
    $ClientID = $params.ClientID
    $CertificatePath = $params.CertificatePath
    $Option = $params.Option
    
    # Check if PnP PowerShell is installed
    if (-not (Get-Module -ListAvailable -Name "PnP.PowerShell")) {
        Write-Host "PnP.PowerShell module is not installed. Installing now..." -ForegroundColor Yellow
        Install-Module -Name "PnP.PowerShell" -Scope CurrentUser -Force
    }
    
    # Display audit options
    if ($Option -eq 1) {
        Write-Host "Will audit only top-level folders" -ForegroundColor Green
    } else {
        Write-Host "Will audit ALL folders and subfolders" -ForegroundColor Yellow
    }
    
    # Connect to SharePoint
    Write-Host "Connecting to site: $SiteUrl" -ForegroundColor Yellow
    Connect-PnPOnline -Url $SiteUrl -ClientId $ClientID -CertificatePath $CertificatePath -Tenant "$TenantName.onmicrosoft.com"
    
    $web = Get-PnPWeb
    Write-Host "Connected to site: $($web.Title)" -ForegroundColor Green
    
    # Get the document library
    $library = Get-PnPList -Identity $LibraryName -ErrorAction SilentlyContinue
    
    if ($null -eq $library) {
        # Try alternate name
        $library = Get-PnPList -Identity "Shared Documents" -ErrorAction SilentlyContinue
        
        if ($null -eq $library) {
            Write-Host "Could not find document library. Available libraries:" -ForegroundColor Red
            Get-PnPList | Where-Object { $_.BaseTemplate -eq 101 } | ForEach-Object { 
                Write-Host "  - $($_.Title)" -ForegroundColor Cyan 
            }
            throw "Library not found"
        }
    }
    
    Write-Host "Found library: $($library.Title)" -ForegroundColor Green
    
    # Create a results array
    $results = New-Object System.Collections.ArrayList
    
    # Get the root folder permissions first (for reference)
    Write-Host "Getting library root permissions..." -ForegroundColor Cyan
    $rootPermissions = @()
    
    $context = Get-PnPContext
    $context.Load($library.RoleAssignments)
    $context.Load($library.RootFolder)
    $context.ExecuteQuery()
    
    foreach ($roleAssignment in $library.RoleAssignments) {
        $context.Load($roleAssignment.Member)
        $context.Load($roleAssignment.RoleDefinitionBindings)
        $context.ExecuteQuery()
        
        foreach ($roleDef in $roleAssignment.RoleDefinitionBindings) {
            $rootPermission = [PSCustomObject]@{
                FolderPath = $library.RootFolder.ServerRelativeUrl
                HasUniquePermissions = $true
                PrincipalType = $roleAssignment.Member.PrincipalType
                PrincipalName = $roleAssignment.Member.Title
                PrincipalLogin = $roleAssignment.Member.LoginName
                PermissionLevel = $roleDef.Name
            }
            $rootPermissions += $rootPermission
            [void]$results.Add($rootPermission)
        }
    }
    
    # OPTION 1: Get only top-level folders
    if ($Option -eq 1) {
        # Directly get the folders under the document library
        Write-Host "Getting top-level folders..." -ForegroundColor Cyan
        
        # First approach - use FolderSiteRelativeUrl method
        try {
            $folders = Get-PnPFolderItem -FolderSiteRelativeUrl $library.RootFolder.ServerRelativeUrl -ItemType Folder
            Write-Host "Found $($folders.Count) folders using FolderSiteRelativeUrl method" -ForegroundColor Green
        }
        catch {
            Write-Host "Error with first method, trying alternate approach..." -ForegroundColor Yellow
            # Second approach - try to get folders differently
            $folders = @()
            $items = Get-PnPListItem -List $library -PageSize 500 | Where-Object { $_["ContentType"] -eq "Folder" -and $_["FileDirRef"] -eq $library.RootFolder.ServerRelativeUrl }
            
            foreach ($item in $items) {
                $context = Get-PnPContext
                $folder = $web.GetFolderByServerRelativeUrl("$($library.RootFolder.ServerRelativeUrl)/$($item['FileLeafRef'])")
                $context.Load($folder)
                $context.ExecuteQuery()
                $folders += $folder
            }
            
            Write-Host "Found $($folders.Count) folders using alternate method" -ForegroundColor Green
        }
        
        # Process each folder
        foreach ($folder in $folders) {
            $folderPath = $folder.ServerRelativeUrl
            Write-Host "Processing folder: $folderPath" -ForegroundColor Cyan
            
            try {
                # Get the list item for the folder
                $listItem = $folder.ListItemAllFields
                $context = Get-PnPContext
                $context.Load($listItem)
                $context.ExecuteQuery()
                
                # Check if folder has unique permissions
                $hasUniquePermissions = $false
                try {
                    $hasUniquePermissions = $listItem.HasUniqueRoleAssignments
                }
                catch {
                    # If we can't determine, assume it inherits
                    $hasUniquePermissions = $false
                }
                
                if ($hasUniquePermissions) {
                    Write-Host "  Folder has UNIQUE permissions" -ForegroundColor Magenta
                    
                    # Get the specific permissions
                    $context.Load($listItem.RoleAssignments)
                    $context.ExecuteQuery()
                    
                    foreach ($roleAssignment in $listItem.RoleAssignments) {
                        $context.Load($roleAssignment.Member)
                        $context.Load($roleAssignment.RoleDefinitionBindings)
                        $context.ExecuteQuery()
                        
                        foreach ($roleDef in $roleAssignment.RoleDefinitionBindings) {
                            $folderPermission = [PSCustomObject]@{
                                FolderPath = $folderPath
                                HasUniquePermissions = $true
                                PrincipalType = $roleAssignment.Member.PrincipalType
                                PrincipalName = $roleAssignment.Member.Title
                                PrincipalLogin = $roleAssignment.Member.LoginName
                                PermissionLevel = $roleDef.Name
                            }
                            [void]$results.Add($folderPermission)
                        }
                    }
                }
                else {
                    Write-Host "  Folder INHERITS permissions" -ForegroundColor DarkGray
                    
                    # Copy the root permissions
                    foreach ($rootPerm in $rootPermissions) {
                        $folderPermission = [PSCustomObject]@{
                            FolderPath = $folderPath
                            HasUniquePermissions = $false
                            PrincipalType = $rootPerm.PrincipalType
                            PrincipalName = $rootPerm.PrincipalName
                            PrincipalLogin = $rootPerm.PrincipalLogin
                            PermissionLevel = $rootPerm.PermissionLevel
                        }
                        [void]$results.Add($folderPermission)
                    }
                }
            }
            catch {
                Write-Host "  Error processing folder: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
    # OPTION 2: Get all folders and subfolders
    else {
        Write-Host "Starting deep scan of all folders and subfolders..." -ForegroundColor Yellow
        
        # Function to recursively process a folder and its subfolders
        function Process-FolderAndSubfolders {
            param (
                [Parameter(Mandatory = $true)]
                [string] $FolderUrl,
                [Parameter(Mandatory = $false)]
                [array] $ParentPermissions,
                [int] $Level = 0
            )
            
            $indent = "  " * $Level
            Write-Host "$indent Processing folder: $FolderUrl" -ForegroundColor Cyan
            
            try {
                # Get the folder
                $folder = Get-PnPFolder -Url $FolderUrl
                
                # Skip the root folder (already processed)
                if ($FolderUrl -ne $library.RootFolder.ServerRelativeUrl) {
                    # Get the list item for the folder
                    $listItem = $folder.ListItemAllFields
                    $context = Get-PnPContext
                    $context.Load($listItem)
                    $context.ExecuteQuery()
                    
                    # Check if folder has unique permissions
                    $hasUniquePermissions = $false
                    try {
                        $hasUniquePermissions = $listItem.HasUniqueRoleAssignments
                    }
                    catch {
                        # If we can't determine, assume it inherits
                        $hasUniquePermissions = $false
                    }
                    
                    $folderPermissions = @()
                    
                    if ($hasUniquePermissions) {
                        Write-Host "$indent   Folder has UNIQUE permissions" -ForegroundColor Magenta
                        
                        # Get the specific permissions
                        $context.Load($listItem.RoleAssignments)
                        $context.ExecuteQuery()
                        
                        foreach ($roleAssignment in $listItem.RoleAssignments) {
                            $context.Load($roleAssignment.Member)
                            $context.Load($roleAssignment.RoleDefinitionBindings)
                            $context.ExecuteQuery()
                            
                            foreach ($roleDef in $roleAssignment.RoleDefinitionBindings) {
                                $folderPermission = [PSCustomObject]@{
                                    FolderPath = $FolderUrl
                                    HasUniquePermissions = $true
                                    PrincipalType = $roleAssignment.Member.PrincipalType
                                    PrincipalName = $roleAssignment.Member.Title
                                    PrincipalLogin = $roleAssignment.Member.LoginName
                                    PermissionLevel = $roleDef.Name
                                }
                                $folderPermissions += $folderPermission
                                [void]$results.Add($folderPermission)
                            }
                        }
                    }
                    else {
                        Write-Host "$indent   Folder INHERITS permissions" -ForegroundColor DarkGray
                        
                        # Copy parent permissions
                        foreach ($parentPerm in $ParentPermissions) {
                            $folderPermission = [PSCustomObject]@{
                                FolderPath = $FolderUrl
                                HasUniquePermissions = $false
                                PrincipalType = $parentPerm.PrincipalType
                                PrincipalName = $parentPerm.PrincipalName
                                PrincipalLogin = $parentPerm.PrincipalLogin
                                PermissionLevel = $parentPerm.PermissionLevel
                            }
                            $folderPermissions += $folderPermission
                            [void]$results.Add($folderPermission)
                        }
                    }
                    
                    # For recursive processing, use this folder's permissions
                    $permissionsToPass = $folderPermissions
                }
                else {
                    # For root folder, use its permissions
                    $permissionsToPass = $rootPermissions
                }
                
                # Get subfolders
                try {
                    $subFolders = Get-PnPFolderItem -FolderSiteRelativeUrl $FolderUrl -ItemType Folder
                    
                    if ($subFolders.Count -gt 0) {
                        Write-Host "$indent   Found $($subFolders.Count) subfolders" -ForegroundColor Green
                        
                        foreach ($subFolder in $subFolders) {
                            Process-FolderAndSubfolders -FolderUrl $subFolder.ServerRelativeUrl -ParentPermissions $permissionsToPass -Level ($Level + 1)
                        }
                    }
                }
                catch {
                    Write-Host "$indent   Error getting subfolders: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            catch {
                Write-Host "$indent Error processing folder: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        
        # Start recursive processing from the root folder
        Process-FolderAndSubfolders -FolderUrl $library.RootFolder.ServerRelativeUrl -ParentPermissions $rootPermissions
    }
    
    # Export results to CSV
    $results | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
    
    Write-Host "Audit complete. Found $($results.Count) permission entries." -ForegroundColor Green
    $uniqueCount = ($results | Where-Object { $_.HasUniquePermissions -eq $true }).Count
    Write-Host "Entries with unique permissions: $uniqueCount" -ForegroundColor Magenta
    Write-Host "Entries with inherited permissions: $($results.Count - $uniqueCount)" -ForegroundColor DarkGray
    Write-Host "Results exported to $CsvPath" -ForegroundColor Green
}
catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    # Disconnect
    Disconnect-PnPOnline
}
