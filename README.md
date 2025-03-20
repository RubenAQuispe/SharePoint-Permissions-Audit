# SharePoint Permissions Audit Tool

A PowerShell script for auditing permissions on SharePoint Online folders with options for different levels of depth.

## Features

- Audit permissions for all top-level folders
- Optionally audit all subfolders at any depth
- Certificate-based authentication using App Registration
- Shows all users with access to folders, even with inherited permissions
- Exports results to CSV for easy analysis
- Multiple folder detection methods for maximum reliability

## Requirements

- PowerShell 5.1 or higher
- PnP PowerShell module
- SharePoint Online site
- App Registration in Microsoft Entra ID (Azure AD) with appropriate permissions
- Certificate for authentication

## Setup

### 1. Create an Entra ID App Registration

Follow the steps in this article to create an app registration in Azure AD. Make sure you grant the app the following permissions:

**Graph API**
* Sites.Read.All
* Directory.Read.All

**SharePoint API**
* Sites.FullControl.All
* User.Read.All

### 2. Create and Upload a Certificate

1. Generate a self-signed certificate:

```powershell
$cert = New-SelfSignedCertificate -Subject "CN=SharePointPermissionsAudit" -CertStoreLocation "Cert:\CurrentUser\My" -KeyExportPolicy Exportable -KeySpec Signature -KeyLength 2048 -KeyAlgorithm RSA -HashAlgorithm SHA256
```

2. Export the certificate to a PFX file:

```powershell
$certPassword = ConvertTo-SecureString -String "YourSecurePassword" -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath C:\Temp\SharePointAudit.pfx -Password $certPassword
```

3. Export the public certificate:

```powershell
Export-Certificate -Cert $cert -FilePath C:\Temp\SharePointAudit.cer
```

4. Upload the public certificate (.cer file) to your App Registration in Azure AD.

### 3. Install PnP PowerShell

```powershell
Install-Module -Name "PnP.PowerShell" -Scope CurrentUser -Force
```

## Usage

### Basic Usage

```powershell
.\SharePoint-Permissions-Audit.ps1
```

This will prompt you for all required parameters and execution options.

### Parameters

```powershell
.\SharePoint-Permissions-Audit.ps1 -TenantName "yourtenant" -SiteUrl "https://yourtenant.sharepoint.com/sites/yoursite" -ClientID "your-app-id" -CertificatePath "C:\path\to\certificate.pfx" -Option 1
```

- **TenantName**: Your Microsoft 365 tenant name (e.g., "contoso" for contoso.sharepoint.com)
- **SiteUrl**: Full URL of the SharePoint site
- **ClientID**: The Client ID (Application ID) of your app registration
- **CertificatePath**: Path to the PFX certificate file
- **LibraryName**: Name of the document library to audit (default: "Documents")
- **CsvPath**: Path where to save the CSV output file (default: Desktop)
- **Option**: 1 = Audit only top-level folders, 2 = Audit all folders and subfolders

## Output

The script creates a CSV file with the following columns:

- **FolderPath**: The server-relative URL of the folder
- **HasUniquePermissions**: Whether the folder has unique or inherited permissions
- **PrincipalType**: The type of security principal (User, Group, etc.)
- **PrincipalName**: Display name of the user or group
- **PrincipalLogin**: Login name or email of the user
- **PermissionLevel**: The permission level (Read, Contribute, Edit, Full Control, etc.)

## Troubleshooting

### Script is not finding any folders

The script uses multiple methods to find folders. If it's still not finding folders:

1. Check if you have sufficient permissions to access the folders
2. Verify the document library name is correct
3. Make sure the App Registration has the necessary permissions and they're admin-consented

### Authentication issues

If you're experiencing authentication issues:

1. Ensure the certificate is valid and properly registered with the app
2. Verify that the app has been granted sufficient permissions
3. Make sure admin consent has been provided for the permissions

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- [PnP PowerShell](https://pnp.github.io/powershell/) - Used for SharePoint interactions
- [Microsoft Graph Documentation](https://docs.microsoft.com/en-us/graph/)
- [SharePoint Online Management Shell](https://docs.microsoft.com/en-us/powershell/sharepoint/sharepoint-online/connect-sharepoint-online)
