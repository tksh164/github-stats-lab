#Requires -Version 7

param (
    [Parameter(Mandatory = $true)]
    [string] $TargetRepoFilePath,

    [Parameter(Mandatory = $true)]
    [string] $OutputFolderPath
)

$today = (Get-Date).ToString('yyyy-MM-dd')

$targets = Get-Content -Encoding utf8 -Raw -LiteralPath $TargetRepoFilePath | ConvertFrom-Json -Depth 2
foreach ($target in $targets) {
    $owner = $target.owner
    $repo  = $target.repo

    # Create the output folder if it does not exist.
    $resultFolderName = '{0}-{1}' -f $owner, $repo
    $resultFolderPath = Join-Path -Path $OutputFolderPath -ChildPath $resultFolderName
    if (-not (Test-Path -PathType Container -LiteralPath $resultFolderPath)) {
        New-Item -ItemType Directory -Path $resultFolderPath 
    }
    
    # Retrieve the existing result from the file.
    $resultFileName = 'downloads_{0}_{1}_{2}.json' -f (Get-Date).ToString('yyyy'), $owner, $repo
    $resultFilePath = Join-Path -Path $resultFolderPath -ChildPath $resultFileName
    $result = @()
    if (Test-Path -PathType Leaf -LiteralPath $resultFilePath) {
        $result += Get-Content -Encoding utf8 -Raw -LiteralPath $resultFilePath | ConvertFrom-Json -Depth 2
    }

    # Retrieve the release of the target repository.
    $params = @{
        Uri     = 'https://api.github.com/repos/{0}/{1}/releases' -f $owner, $repo
        Method  = 'Get'
        Headers = @{
            Authorization = 'Bearer {0}' -f $env:GITHUB_TOKEN
        }
    }
    $response = Invoke-RestMethod @params

    # Aggregate the download count of each release.
    $result += $response | ForEach-Object -Process {
        $release = $_
        if (-not $release.draft) {
            [PSCustomObject] @{
                date          = $today
                tagName       = $release.tag_name
                downloadCount = [int] ($release.assets | Measure-Object -Sum -Property 'download_count').Sum
            }
        }
    }

    # Remove the duplicated results. If date and tag name pair is the same, it is considered as a duplicate.
    $dedupBag = @{}
    $result | ForEach-Object -Process {
        $dedupKey = $_.date + '_' + $_.tagName
        $dedupBag[$dedupKey] = $_
    }
    $newResult = $dedupBag.Values | Sort-Object -Property 'date', 'tagName'

    # Write the result to a file.
    if ($newResult.Length -eq 1) {
        $newResult = ,$newResult
    }
    ,$newResult | ConvertTo-Json -Depth 2 | Out-File -Encoding utf8 -LiteralPath $resultFilePath -Force
}
