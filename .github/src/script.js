async function createRunCheck(github, inputs, name, status = "in_progress") {
    // https://docs.github.com/en/rest/checks/runs?apiVersion=2022-11-28#create-a-check-run
    const repo_data = inputs.repo_name.split("/");
    const commit_sha = inputs.commit_sha;
    const owner = repo_data[0];
    const repo = repo_data[1];
    console.log(github);
    console.log(github.server_url);
    console.log(github.repository);
    console.log(github.repository);
    console.log(github.run_id);
    const check_url = `${github.server_url}/${github.repository}/actions/runs/${github.run_id}`;
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
