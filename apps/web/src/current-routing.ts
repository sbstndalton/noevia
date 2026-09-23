import type { Message, RoutingDecision } from './types';

/** Only the latest assistant turn in the visible chat can describe the current reply. */
export function currentRoutingDecision(messages: Message[], chatVisible: boolean): RoutingDecision | null {
  if (!chatVisible) return null;
  const latest = messages[messages.length - 1];
  return latest?.role === 'assistant' ? latest.routingDecision ?? null : null;
}
