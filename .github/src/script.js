export async function createRunCheck(github, inputs, name, status = "in_progress") {
    // https://docs.github.com/en/rest/checks/runs?apiVersion=2022-11-28#create-a-check-run
    const repo_data = inputs.repo_name.split("/");
    const commit_sha = inputs.commit_sha;
    const owner = repo_data[0];
    const repo = repo_data[1];

    const response = await github.rest.checks.create({
        owner,
        repo,
        head_sha: commit_sha,
        name,
        status,
    });

    return response.data.id;
}

export async function updateRunCheck(github, inputs, check_run_id, status = "completed", conclusion = "success") {
    // https://docs.github.com/en/rest/checks/runs?apiVersion=2022-11-28#create-a-check-run
    const repo_data = inputs.repo_name.split("/");
    const owner = repo_data[0];
    const repo = repo_data[1];

    const response = await github.rest.checks.update({
        owner,
        repo,
        check_run_id,
        status,
        conclusion,
    });
}
