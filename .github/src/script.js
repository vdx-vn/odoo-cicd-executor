async function createRunCheck({ ...kwargs }) {
    // https://docs.github.com/en/rest/checks/runs?apiVersion=2022-11-28#create-a-check-run
    const github = kwargs.github;
    const context = kwargs.context;
    const core = kwargs.core;
    const repo_data = core.getInput("repo_name").split("/");
    const commit_sha = core.getInput("commit_sha");
    const owner = repo_data[0];
    const repo = repo_data[1];
    const check_url = `${context.serverUrl}/${context.payload.repository.full_name}/actions/runs/${context.runId}`;
    const name = kwargs.name;
    const status = kwargs.status || "in_progress";

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
