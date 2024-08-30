// fixme: make all value from workflow available here to prevent put all param to function
export async function createRunCheck(github, inputs) {
    const repo_data = inputs.repo_name.split("/");
    const commit_sha = inputs.commit_sha;
    const owner = repo_data[0];
    const repo = repo_data[1];

    console.log(owner);
    console.log(repo);

    const response = await github.rest.checks.create({
        owner: owner,
        repo: repo,
        head_sha: commit_sha,
        name: "Oh yeah luon",
        status: "in_progress",
    });

    return response.data.id;
}
