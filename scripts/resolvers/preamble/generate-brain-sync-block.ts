/**
 * artifacts-sync preamble block (gbrain content stripped).
 *
 * Emits minimal bash that reports ARTIFACTS_SYNC: off at every skill
 * invocation. All gbrain-specific logic (context-load hints, MCP mode
 * detection, privacy stop-gate, skill-end sync) has been removed.
 *
 * The full gbrain integration lives in the gbrain host config and the
 * sync-gbrain / setup-gbrain skills for those who need it.
 */
import type { TemplateContext } from '../types';

export function generateBrainSyncBlock(_ctx: TemplateContext): string {
  return `## Artifacts Sync (skill start)

\`\`\`bash
echo "ARTIFACTS_SYNC: off"
\`\`\``;
}
