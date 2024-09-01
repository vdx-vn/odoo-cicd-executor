export async function updateRunCheck(github, inputs, check_run_id, status = "completed", conclusion = "success") {
    // https://docs.github.com/en/rest/checks/runs?apiVersion=2022-11-28#create-a-check-run
    const repo_data = inputs.repo_name.split("/");
    const owner = repo_data[0];
    const repo = repo_data[1];

    await github.rest.checks.update({
        owner,
        repo,
        check_run_id,
        status,
        conclusion,
    });
}
