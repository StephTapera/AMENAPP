export type AmenAgentTaskType =
  | "summarize_sermon"
  | "create_post"
  | "explain_video"
  | "generate_prayer"
  | "create_church_notes"
  | "draft_announcement"
  | "extract_action_items"
  | "moderate_content"
  | "translate_content"
  | "generate_graphic_prompt";

export function routeAgentTask(taskType: AmenAgentTaskType): string {
    return taskType;
}
