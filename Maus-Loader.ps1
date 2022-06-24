function Download-Video {
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory = $true, ValueFromPipeline, Position = 1)]
		[ValidateNotNullOrEmpty()]
		[string]
		$Link,
        	[Parameter(Mandatory = $false)]
		[switch]
		$Overwrite,
        	[Parameter(Mandatory = $false)]
		[switch]
		$Skip,
        	[Parameter(Mandatory = $false)]
		[switch]
		$Silent
	)

    $OutputDir = Join-Path -Path (Resolve-Path -Path ".\") -ChildPath Output
    if (![IO.Directory]::Exists($OutputDir)) {   
        try {
            $OutputDir = New-Item -Path $OutputDir -ItemType Directory -Force
        }
        catch {
            Write-Verbose "Output directory could not be created"
            Write-Verbose "Using working directory instead"
            $OutputDir = Resolve-Path -Path ".\"
        }
        
    } else {
        $OutputDir = Get-Item -Path $OutputDir
    }

    # Base link to video viewing screen
    try {
        $Page = Invoke-WebRequest -UseB -Uri $Link
    }
    catch {
        Write-Error "Download Failed with $Link"
        Exit
    }

    $Page = $Page.Content
    $i = $Page.IndexOf('class="videoButton play srtvd"')
    $l = $Page.Substring($i).IndexOf(">")
    $Page = $Page.Substring($i, $l)
    $i = $Page.IndexOf("'url': ")
    $l = $Page.Substring($i).IndexOf(",")
    $Page = $Page.Substring($i, $l)
    $NextLink = $Page.Substring(7).Replace("'", "")
    
    # Javascript file of play button
    try {
        $Page = Invoke-WebRequest -UseB -Uri $NextLink
    }
    catch {
        Write-Error "Download Failed with $Link"
        Exit
    }

    $Page = $Page.Content
    $i = $Page.IndexOf("{")
    $l = $Page.Substring($i).LastIndexOf("}") + 1
    $Page = $Page.Substring($i, $l)
    $Page = $Page | ConvertFrom-Json

    $FileLink = $Page.mediaResource.alt.videoURL.Substring(2)
    $Name = $Page.trackerData.trackerClipTitle.Replace(":", "")
    $MediaFormat = $page.mediaResource.alt.mediaFormat

    if ($MediaFormat.Equals("mp4"))
    {   
        $FileName = $Name + "." + $MediaFormat
        $FilePath = Join-Path -Path $OutputDir -ChildPath $FileName

        if (![IO.File]::Exists($FilePath) -or $Overwrite)
        {
            $Download = $true
        }
        elseif (!$Skip)
        {
            Write-Host ("File " + '"' + $FileName + '"' + " already exists.")
            $Option = Read-Host ("Overwrite File? [y/N]")
            $Download = $Option.ToLower().Equals("y")
            Write-Host
        }

        if ($Download)
        {   
            if (!$Silent)
            {
                Write-Host ("Downloading File: " + '"' + $FileName + '"' + "...")
            }
            
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -UseB -Uri $FileLink -OutFile $FilePath
            
            if (!$Silent)
            {
                Write-Host "Done"
                Write-Host
            }
        }
    }
    elseif ($MediaFormat.Equals("hls"))
    {   
        $FileName = $Name + ".ts"
        $FilePath = Join-Path -Path $OutputDir -ChildPath $FileName

        $Page = Invoke-WebRequest -UseB -Uri $FileLink
        $Page = [Text.Encoding]::ASCII.GetString($Page.Content).Split("`n")
        $Resolutions = $Page | 
        Where-Object -FilterScript {$_.Contains("RESOLUTION")} | 
        ForEach-Object {
            $i = $_.IndexOf("RESOLUTION")
            $l = $_.Substring($i).IndexOf(",")
            $m = $_.Substring($i, $l).Split("=")[1]
            Write-Output $m
        }

        $Value = -1
        $Resolution = 0
        for ($i = 0; $i -lt $Resolutions.Count; $i++) {
            $m = $Resolutions[$i].Split("x")
            $n = [int]$m[0]*[int]$m[1]
            if ($n -gt $Value)
            {
                $Value = $n
                $Resolution = $Resolutions[$i]
            }
        }

        $Index = -1
        for ($i = 0; $i -lt $Page.Count; $i++) {
            if ($Page[$i].Contains($Resolution))
            {
                $Index = $i
            }
        }

        try {
            $FileLink = $Page[$Index+1]
        }
        catch {
            Write-Error "Unable to select resolution"
            Exit
        }

        $Page = Invoke-WebRequest -UseB -Uri $FileLink
        $Page = [Text.Encoding]::ASCII.GetString($Page.Content).Split("`n")
        $Links = $Page | 
        Where-Object -FilterScript {$_.Contains("http")}

        if (![IO.File]::Exists($FilePath) -or $Overwrite)
        {
            $Download = $true
        }
        elseif (!$Skip)
        {
            Write-Host ("File " + '"' + $FileName + '"' + " already exists.")
            $Option = Read-Host ("Overwrite File? [y/N]")
            $Download = $Option.ToLower().Equals("y")
            Write-Host
        }

        if ($Download)
        {   
            if (!$Silent)
            {
                Write-Host ("Downloading File: " + '"' + $FileName + '"' + "...")
            }
            
            $FileStream = [IO.File]::OpenWrite($FilePath)

            $ProgressPreference = 'SilentlyContinue'
            for ($i = 0; $i -lt $Links.Count; $i++) {
                $ReadData = (Invoke-WebRequest -UseB -Uri $Links[$i]).Content
                $FileStream.Write($ReadData, 0, $ReadData.Length)
                Write-Verbose ("Downloaded Part " + ($i + 1) + " out of " + $Links.Count)
            }

            $FileStream.Close()
            
            if (!$Silent)
            {
                Write-Host "Done"
                Write-Host
            }
        }
    }
    else
    {
        Write-Error "Unsupported Media Format $MediaFormat"
        Exit
    }

    return @{"Name" = $Name; "FileName" = $FileName; "FilePath" = $FilePath}
}

function Play-Video {
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory = $true, ValueFromPipeline)]
		[ValidateNotNullOrEmpty()]
		[string]
		$FilePath
	)

    Add-Type -AssemblyName presentationCore
    Add-Type -AssemblyName presentationFramework
    Add-Type -AssemblyName System.Windows.Forms
    #[System.Windows.Forms.Application]::EnableVisualStyles()

    $MediaPlayer = New-Object Windows.Media.MediaPlayer

    $VideoDrawing = New-Object Windows.Media.VideoDrawing
    $VideoDrawing.Rect = New-Object Windows.Rect (0, 0, 100, 100)
    $VideoDrawing.Player = $MediaPlayer

    $DrawingBrush = New-Object Windows.Media.DrawingBrush ($VideoDrawing)

    $Window = New-Object Windows.Window
    $Window.Background = $DrawingBrush
    #$Window.Height = $MediaPlayer.NaturalVideoHeight
    #$Window.Width = $MediaPlayer.NaturalVideoWidth
    $Window.Show()


    $MediaPlayer.Open($FilePath)
    $MediaPlayer.Play()
    while (!$MediaPlayer.Position.Equals($MediaPlayer.NaturalDuration.TimeSpan))
    {
        Start-Sleep -Milli 10
    }

    $Window.Close()
}


$BaseUrl = "https://www.wdrmaus.de/"
$ListUrl = "https://www.wdrmaus.de/filme/sachgeschichten/index.php5?filter=alle"
$Page = Invoke-WebRequest -Uri $ListUrl

Write-Host "Processing..."

$List = $Page.Links | 
Where-Object -Property tagName -Value A -EQ | 
Where-Object -FilterScript {$_.href.Contains("filme") -and !$_.href.Contains("filter") -and $_.innerHTML.Contains("img")} | 
Select-Object -Property innerText,href | 
Sort-Object -Property innerText

$List | Select-Object -Property innerText | Format-Wide -Column 4

$Result = $List
$Search = $null

while ($Result.Length -ne 1)
{
    $Search = Read-Host "Search"

    if ($Search.Equals("*"))
    {
        break
    }

    $ResultC = [array]($List | Where-Object -Property innerText -Value $Search -CMatch)
    $ResultM = [array]($List | Where-Object -Property innerText -Value $Search -EQ)
    
    if ($ResultM.Length -eq 1)
    {
    	$Result = $ResultM
    }
    else
    {
    	$Result = $ResultC
    }
    
    $Result | Select-Object -Property innerText | Format-Wide -Column 4
    Write-Host ($Result.Length.ToString() + " Results")
    Write-Host
}

if ($Result.Length -eq 1)
{
    $Selected = $Result[0]
    $Link = ($BaseUrl + $Selected.href).Replace("../", "")

    try {
        $FileInfo = Download-Video -Link $Link
        $FilePath = $FileInfo.FilePath
        $Name = $FileInfo.Name
    }
    catch {
        Write-Error "Download Failed with $Link"
        Exit
    }
    
    Write-Host

    $Option = Read-Host ("Play Video " + '"' + $Name + '"' + "? [Y/n]")
    if ($Option.ToLower().Equals("n"))
    {
        Exit
    }
    else {
        try {
            Play-Video -FilePath $FilePath
        }
        catch {
            Write-Error "Video Playback Failed"
            Exit
        }
    }
}
else 
{
    Write-Host "Downloading all Files..."
    $Option = Read-Host ("Continue with downloading " + $List.Length + " files? [Y/n]")
    if ($Option.ToLower().Equals("n"))
    {
        Exit
    }

    Write-Host "Continuing with download..."
    
    for ($i = 0; $i -lt $List.Length; $i++) {
        $Link = ($BaseUrl + $List[$i].href).Replace("../", "")
        try {
            Download-Video -Link $Link -Skip -Silent | Out-Null
            Write-Host ("Downloaded file " + ($i + 1) + " out of " + $List.Length)
        }
        catch {
            try {
                Download-Video -Link $Link -Overwrite -Silent | Out-Null
                Write-Host ("Downloaded file " + ($i + 1) + " out of " + $List.Length)
            }
            catch {
                Write-Error ("Unable to Download Video " + ($i + 1))
            }
        }
    }

    Write-Host "Done"
}



