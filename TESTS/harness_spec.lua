-- TESTS/harness_spec.lua — the cleanup helpers of TESTS/harness.lua.
--
-- The specs share one editor (`isolated = "none"`), so a cleanup helper that
-- silently does nothing turns into state-guard failures in unrelated specs.

return function(H)
  local eq, ok = H.eq, H.ok

  -- `opts.vars`: the values are taken at snapshot time. `vim.deepcopy(vim.g)`
  -- would copy the proxy's metatable and read the live value at restore time,
  -- making the restore a no-op.
  vim.g.docmap_harness_spec_set = 1
  vim.g.docmap_harness_spec_unset = nil
  local opts = { vars = { "docmap_harness_spec_set", "docmap_harness_spec_unset" } }
  local snap = H.snapshot(opts)
  vim.g.docmap_harness_spec_set = 2
  vim.g.docmap_harness_spec_unset = "leaked"
  H.restore(snap, opts)
  eq(vim.g.docmap_harness_spec_set, 1, "restore: a changed vim.g key gets its old value back")
  eq(vim.g.docmap_harness_spec_unset, nil, "restore: a key unset at snapshot time is unset again")
  vim.g.docmap_harness_spec_set = nil

  -- `with_restore`: the cleanup runs when the body raises, and the body's
  -- error still reaches the caller unchanged.
  local cmd = "DocmapHarnessSpecLeak"
  local wins_before = #vim.api.nvim_list_wins()
  local ok_run, err = pcall(H.with_restore, { vars = { "docmap_harness_spec_set" } }, function()
    vim.api.nvim_create_user_command(cmd, function() end, {})
    vim.cmd("new")
    vim.g.docmap_harness_spec_set = "leaked"
    error("boom", 0)
  end)
  eq(ok_run, false, "with_restore: the body's error is raised again")
  eq(err, "boom", "with_restore: ...unchanged")
  eq(
    vim.api.nvim_get_commands({ builtin = false })[cmd],
    nil,
    "with_restore: user command removed on error"
  )
  eq(#vim.api.nvim_list_wins(), wins_before, "with_restore: window closed on error")
  eq(vim.g.docmap_harness_spec_set, nil, "with_restore: vim.g key restored on error")

  local ran = false
  H.with_restore(nil, function(s)
    ran = type(s) == "table" and s.bufs ~= nil
  end)
  ok(ran, "with_restore: the body runs and gets the snapshot")

  -- `wipe_new` on a reused `[No Name]` buffer: `:edit` names the empty buffer
  -- the spec found, and whatever attached to the file (Neovim's LSP sets a
  -- buffer-local `K`) leaves its buffer-local mappings there. They go; the
  -- ones the buffer had at the snapshot stay.
  local outer = H.snapshot()
  vim.cmd("new")
  local reused = vim.api.nvim_get_current_buf()
  vim.keymap.set("n", "<Plug>(docmap-harness-kept)", "<Nop>", { buffer = reused })
  local snap_reused = H.snapshot()
  vim.api.nvim_buf_set_name(reused, H.tmpfile("_harness_reused") .. "/reused.lua")
  vim.keymap.set("n", "K", "<Nop>", { buffer = reused })
  H.wipe_new(snap_reused)
  eq(vim.api.nvim_buf_get_name(reused), "", "wipe_new: the reused buffer loses its name")
  eq(
    vim.fn.maparg("K", "n", false, true).buffer,
    nil,
    "wipe_new: a buffer-local mapping added on the reused buffer goes"
  )
  local kept = vim.api.nvim_buf_call(reused, function()
    return vim.fn.maparg("<Plug>(docmap-harness-kept)", "n", false, true).buffer
  end)
  eq(kept, 1, "wipe_new: a buffer-local mapping from before the snapshot stays")
  H.restore(outer)
end
