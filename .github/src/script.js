async function createRunCheck(github, context, inputs, name, status = "in_progress") {
    // https://docs.github.com/en/rest/checks/runs?apiVersion=2022-11-28#create-a-check-run
    const repo_data = inputs.repo_name.split("/");
    const commit_sha = inputs.commit_sha;
    const owner = repo_data[0];
    const repo = repo_data[1];
    console.log(context);
    console.log(context.serverUrl);
    console.log(context.repository.full_name);
    console.log(context.repository);
    console.log(context.runId);
    const check_url = `${context.serverUrl}/${context.repository}/actions/runs/${context.runId}`;
    console.log("url ", check_url);

    const response = await github.rest.checks.create({
        owner,
        repo,
        head_sha: commit_sha,
        name,
        status,
        output: {
            title: name,
            summary: "",
            text: "",
        },
        details_url: check_url,
    });

    return response.data.id;
}

async function updateRunCheck(github, inputs, check_run_id, status = "completed", conclusion = "success") {
    // https://docs.github.com/en/rest/checks/runs?apiVersion=2022-11-28#update-a-check-run
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

export default { createRunCheck, updateRunCheck };
