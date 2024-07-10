 get_terraform_plan_output() {
    projectName=$1
    pipelineId=$2
    runId=$3

    # URI per ottenere i log dell'esecuzione
    uriLogs="$UriOrga/$projectName/_apis/pipelines/$pipelineId/runs/$runId/logs?api-version=5.1-preview.1"
    logs=$(curl -s -H "$AzureDevOpsAuthenicationHeader" $uriLogs)

    # Iterare sui log per trovare l'output di terraform plan
    echo "$logs" | jq -r '.value[] | select(.url | test("terraform plan")) | .url' | while read logUrl; do
        logOutput=$(curl -s -H "$AzureDevOpsAuthenicationHeader" $logUrl)
        echo "$logOutput" | grep -A100 "Terraform Plan Output" >> "terraform_plan_$projectName_$pipelineId_$runId.csv"
    done
}
# Funzione per scaricare gli artefatti della pipeline
download_pipeline_artifact() {
    projectName=$1
    pipelineId=$2
    runId=$3

    # URI per ottenere gli artefatti dell'esecuzione
    uriArtifacts="$UriOrga/$projectName/_apis/pipelines/$pipelineId/runs/$runId/artifacts?api-version=5.1-preview.1"
    artifacts=$(curl -s -H "$AzureDevOpsAuthenicationHeader" $uriArtifacts)

    # Scaricare l'artefatto di terraform plan
    artifactUrl=$(echo "$artifacts" | jq -r '.value[] | select(.name == "terraform-plan-output") | .resource.downloadUrl')
    if [ "$artifactUrl" != "" ]; then
        curl -s -H "$AzureDevOpsAuthenicationHeader" -o "terraform_plan_$projectName_$pipelineId_$runId.zip" "$artifactUrl"
        unzip "terraform_plan_$projectName_$pipelineId_$runId.zip" -d "terraform_plan_$projectName_$pipelineId_$runId"
        mv "terraform_plan_$projectName_$pipelineId_$runId/terraform_plan_output.csv" "terraform_plan_$projectName_$pipelineId_$runId.csv"
        rm -rf "terraform_plan_$projectName_$pipelineId_$runId.zip" "terraform_plan_$projectName_$pipelineId_$runId"
    else
        echo "Nessun artefatto trovato per terraform plan"
    fi
}


# Iterazione sui progetti e avvio delle pipeline
echo "$Projects" | jq -r '.value[] | .name' | while read projectName; do
    echo "Lanciando pipeline per il progetto: $projectName"

    # Ottenere le pipeline del progetto
    uriPipelines="$UriOrga/$projectName/_apis/pipelines?api-version=6.0-preview.1"
    Pipelines=$(curl -s -H "$AzureDevOpsAuthenicationHeader" $uriPipelines)

    # Iterare sulle pipeline e avviare ciascuna
    echo "$Pipelines" | jq -r '.value[] | .id' | while read pipelineId; do
        uriRunPipeline="$UriOrga/$projectName/_apis/pipelines/$pipelineId/runs?api-version=6.0-preview.1"
        echo "Avviando pipeline ID: $pipelineId per il progetto $projectName"
        
        response=$(curl -s -X POST -H "$AzureDevOpsAuthenicationHeader" -H "Content-Type: application/json" $uriRunPipeline -d '{}')
        runId=$(echo "$response" | jq -r '.id')

        if [ "$runId" != "null" ]; then
            echo "Pipeline $pipelineId avviata con successo con ID esecuzione: $runId"
            
            # Ottenere il risultato di terraform plan e salvarlo in CSV
            get_terraform_plan_output "$projectName" "$pipelineId" "$runId"
        else
            echo "Errore nell'avvio della pipeline $pipelineId per il progetto $projectName"
        fi
    done
done

echo "Tutte le pipeline sono state lanciate."
