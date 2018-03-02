﻿
$parentPath = Split-Path -Path $MyInvocation.MyCommand.Path -Parent

$paramsPathBuildSettings = @{
    Path      =  $parentPath
    ChildPath = "build.settings.ps1"
}

$pathBuildSettings = Join-Path @paramsPathBuildSettings

. $pathBuildSettings

#Synopsis: Run Tests and Fail Build on Error.
task . Clean, Analyze, RunTests, ConfirmTestsPassed

#Synopsis: Clean Artifact directory.
task Clean {
    
    if (Test-Path -Path $Artifacts) {
        Remove-Item "$Artifacts/*" -Recurse -Force
    }

    New-Item -ItemType Directory -Path $Artifacts -Force
    
}

#Synopsis: Analyze code.
task Analyze {
    $scriptAnalyzerParams = @{
        Path = $ModulePath
        ExcludeRule = @('PSPossibleIncorrectComparisonWithNull', 'PSUseToExportFieldsInManifest')
        Severity = @('Error', 'Warning')
        Recurse = $true
        Verbose = $false
    }

    $saResults = Invoke-ScriptAnalyzer @scriptAnalyzerParams
    # Save the results.
    $saResults | ConvertTo-Json | Set-Content (Join-Path $Artifacts "ScriptAnalysisResults.json")
}

#Synopsis: Run tests.
task RunTests {
    $invokePesterParams = @{
        OutputFile = (Join-Path $Artifacts "TestResults.xml")
        OutputFormat = "NUnitXml"
        Strict = $true
        PassThru = $true
        Verbose = $false
        EnableExit = $false
        CodeCoverage = (Get-ChildItem -Path "$ModulePath\*.ps1" -Exclude "*.Tests.*" -Recurse).FullName
    }

    $testResults = Invoke-Pester @invokePesterParams

    $testResults | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $Artifacts "PesterResults.json")
}

#Synopsis: Confirm that tests passed.
task ConfirmTestsPassed {
    # Fail Build after reports are created, this allows CI to publish test results before failing
    [xml]$xml = Get-Content (Join-Path $Artifacts "TestResults.xml")
    $numberFails = $xml."test-results".failures
    assert($numberFails -eq 0) ('Failed "{0}" unit tests.' -f $numberFails)

    # Fail Build if Coverage is under requirement
    $json = Get-Content (Join-Path $Artifacts "PesterResults.json") | ConvertFrom-Json
    $overallCoverage = [Math]::Floor(($json.CodeCoverage.NumberOfCommandsExecuted / $json.CodeCoverage.NumberOfCommandsAnalyzed) * 100)
    assert($OverallCoverage -gt $PercentCompliance) ('A Code Coverage of "{0}" does not meet the build requirement of "{1}"' -f $overallCoverage, $PercentCompliance)
}