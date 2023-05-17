Config = {
  ensure_installed = {}
}

local UPSTREAM = "lspcontainers/"

local supported_languages = {
  bashls = { image = "docker.io/lspcontainers/bash-language-server" },
  clangd = { image = "docker.io/lspcontainers/clangd-language-server" },
  dockerls = { image = "docker.io/lspcontainers/docker-language-server" },
  gopls = {
    cmd_builder = function (runtime, workdir, image, network)
      local volume = workdir..":"..workdir..":z"
      local env = vim.api.nvim_eval('environ()')
      local gopath = env.GOPATH or env.HOME.."/go"
      local gopath_volume = gopath..":"..gopath..":z"

      local group_handle = io.popen("id -g")
      local user_handle = io.popen("id -u")

      local group_id = string.gsub(group_handle:read("*a"), "%s+", "")
      local user_id = string.gsub(user_handle:read("*a"), "%s+", "")

      group_handle:close()
      user_handle:close()

      local user = user_id..":"..group_id

      if runtime == "docker" then
      	network = "bridge"
      elseif runtime == "podman" then
		network = "slirp4netns"
      end

      return {
        runtime,
        "container",
        "run",
        "--env",
        "GOPATH="..gopath,
        "--interactive",
        "--network="..network,
        "--rm",
        "--workdir="..workdir,
        "--volume="..volume,
        "--volume="..gopath_volume,
        "--user="..user,
        image
      }
    end,
    image = "docker.io/lspcontainers/gopls",
  },
  graphql = { image = UPSTREAM + "graphql-language-service-cli" },
  html = { image = UPSTREAM + "html-language-server" },
  intelephense = { image = UPSTREAM + "intelephense" },
  jsonls = { image = UPSTREAM + "json-language-server" },
  omnisharp = { image = UPSTREAM + "omnisharp" },
  powershell_es = { image = UPSTREAM + "powershell-language-server" },
  prismals = { image = UPSTREAM + "prisma-language-server" },
  pylsp = { image = UPSTREAM + "python-lsp-server" },
  pyright = { image = UPSTREAM + "pyright-langserver" },
  rust_analyzer = { image = UPSTREAM + "rust-analyzer" },
  solargraph = { image = UPSTREAM + "solargraph" },
  sumneko_lua = { image = UPSTREAM + "lua-language-server" },
  svelte = { image = UPSTREAM + "svelte-language-server" },
  tailwindcss= { image = UPSTREAM + "tailwindcss-language-server" },
  terraformls = { image = UPSTREAM + "terraform-ls" },
  tsserver = { image = UPSTREAM + "typescript-language-server" },
  vuels = { image = UPSTREAM + "vue-language-server" },
  yamlls = { image = UPSTREAM + "yaml-language-server" },
}

-- default command to run the lsp container
local default_cmd = function (runtime, workdir, image, network, docker_volume)
  if vim.loop.os_uname().sysname == "Windows_NT" then
    workdir = Dos2UnixSafePath(workdir)
  end

  local mnt_volume
  if docker_volume ~= nil then
    mnt_volume ="--volume="..docker_volume..":"..workdir..":z"
  else
    mnt_volume = "--volume="..workdir..":"..workdir..":z"
  end

  return {
    runtime,
    "container",
    "run",
    "--interactive",
    "--rm",
    "--network="..network,
    "--workdir="..workdir,
    mnt_volume,
    image
  }
end

local function command(server, user_opts)
  -- Start out with the default values:
  local opts =  {
    container_runtime = "docker",
    root_dir = vim.fn.getcwd(),
    cmd_builder = default_cmd,
    network = "none",
    docker_volume = nil,
  }

  -- If the LSP is known, it override the defaults:
  if supported_languages[server] ~= nil then
    opts = vim.tbl_extend("force", opts, supported_languages[server])
  end

  -- If any opts were passed, those override the defaults:
  if user_opts ~= nil then
    opts = vim.tbl_extend("force", opts, user_opts)
  end

  if not opts.image then
    error(string.format("lspcontainers: no image specified for `%s`", server))
    return 1
  end

  return opts.cmd_builder(opts.container_runtime, opts.root_dir, opts.image, opts.network, opts.docker_volume)
end

Dos2UnixSafePath = function(workdir)
  workdir = string.gsub(workdir, ":", "")
  workdir = string.gsub(workdir, "\\", "/")
  workdir = "/" .. workdir
  return workdir
end

local function on_event(_, data, event)
  --if event == "stdout" or event == "stderr" then
  if event == "stdout" then
    if data then
      for _, v in pairs(data) do
        print(v)
      end
    end
  end
end

local function images_pull(runtime)
  local jobs = {}
  runtime = runtime or "docker"

  for idx, server_name in ipairs(Config.ensure_installed) do
    local server = supported_languages[server_name]

    local job_id =
      vim.fn.jobstart(
      runtime.." image pull "..server['image'],
      {
        on_stderr = on_event,
        on_stdout = on_event,
        on_exit = on_event,
      }
    )

    table.insert(jobs, idx, job_id)
  end

  local _ = vim.fn.jobwait(jobs)

  print("lspcontainers: Language servers successfully pulled")
end

local function images_remove(runtime)
  local jobs = {}
  runtime = runtime or "docker"

  for _, v in pairs(supported_languages) do
    local job =
      vim.fn.jobstart(
      runtime.." image rm --force "..v['image']..":latest",
      {
        on_stderr = on_event,
        on_stdout = on_event,
        on_exit = on_event,
      }
    )

    table.insert(jobs, job)
  end

  local _ = vim.fn.jobwait(jobs)

  print("lspcontainers: All language servers removed")
end

vim.api.nvim_create_user_command("LspImagesPull", images_pull, {})
vim.api.nvim_create_user_command("LspImagesRemove", images_remove, {})

local function setup(options)
  if options['ensure_installed'] then
    Config.ensure_installed = options['ensure_installed']
  end
end

return {
  command = command,
  images_pull = images_pull,
  images_remove = images_remove,
  setup = setup,
  supported_languages = supported_languages
}
