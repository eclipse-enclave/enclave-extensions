// Copyright (C) 2026 EclipseSource GmbH and others.
//
// This program and the accompanying materials are made available under the
// terms of the MIT License, which is available in the project root.
//
// SPDX-License-Identifier: MIT

import type { PluginAPI } from "@ampcode/plugin"

const MAX_INPUT_LENGTH = 6000

export default function (amp: PluginAPI) {
  // setup.sh derives this value from Amp's final argv after project .env values
  // have been applied. Fail closed when it is absent or has an unknown value.
  // In yolo mode, do not register a handler, so other policy plugins retain
  // their normal behavior.
  if (process.env.ENCLAVE_AMP_APPROVALS === "0") return

  amp.on("tool.call", async (event, ctx) => {
    const serializedInput = JSON.stringify(event.input, null, 2) ?? "{}"
    const input =
      serializedInput.length > MAX_INPUT_LENGTH
        ? `${serializedInput.slice(0, MAX_INPUT_LENGTH)}\n… (truncated)`
        : serializedInput

    let confirmed: boolean
    try {
      confirmed = await ctx.ui.confirm({
        title: `Allow ${event.tool}?`,
        message: `Amp wants to call \`${event.tool}\` with:\n\n\`\`\`json\n${input}\n\`\`\``,
        confirmButtonText: "Allow",
      })
    } catch (error) {
      if (!amp.helpers.isPluginUINotAvailableError(error)) {
        ctx.logger.log("Could not request tool approval", error)
      }
      return {
        action: "error",
        message: `Enclave --no-yolo could not request approval for ${event.tool}.`,
      }
    }

    if (confirmed) return { action: "allow" }

    return {
      action: "reject-and-continue",
      message: `The user rejected ${event.tool}.`,
    }
  })
}
