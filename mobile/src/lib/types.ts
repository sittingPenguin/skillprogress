// Shapes of the rows the app reads. Access is enforced by the database, not by these types.
export type Role = 'admin' | 'coach' | 'guardian' | 'student';

export interface Membership {
  id: string;
  school_id: string;
  role: Role;
  display_name: string;
  status: 'active' | 'revoked';
  schools: { name: string } | null;
}

export interface Student {
  id: string;
  school_id: string;
  display_name: string;
  year_group: string | null;
}

export interface Skill {
  id: string;
  name: string;
  recording_tip: string | null;
  sports: { name: string } | null;
}

export interface Group {
  id: string;
  name: string;
  kind: 'class' | 'coach';
  group_members: { student_id: string }[];
}

export interface Assessment {
  id: string;
  rubric_version_id?: string;
  scores?: Record<string, number>;
  strengths?: string | null;
  to_improve?: string | null;
  status: 'draft' | 'published';
  feedback: string | null;
  next_goal: string | null;
  published_at: string | null;
}

export interface Clip {
  id: string;
  school_id?: string;
  restricted_reason?: string | null;
  student_id: string;
  skill_id: string;
  recorded_on: string;
  uploaded_at: string;
  upload_status: 'uploading' | 'ready' | 'failed';
  storage_path: string | null;
  drill: string | null;
  restricted: boolean;
  skills: { name: string } | null;
  students: { display_name: string } | null;
  assessments: Assessment | Assessment[] | null;
}

export const firstAssessment = (c: Clip): Assessment | null =>
  Array.isArray(c.assessments) ? c.assessments[0] ?? null : c.assessments;

export interface RubricCriterion { key: string; name: string; descriptors: string[] }
export interface RubricVersion { id: string; skill_id: string; version: number; levels: string[]; criteria: RubricCriterion[] }

export interface Moment { id: string; at_ms: number; body: string; author_id: string }

export type GoalStatus = 'in_progress' | 'achieved' | 'replaced';
export interface Goal {
  id: string; student_id: string; skill_id: string | null; text: string; status: GoalStatus; notes: string | null;
  clip_id: string | null; published: boolean; set_on: string; closed_on: string | null; skills: { name: string } | null;
}

export const CLIP_SELECT =
  'id, school_id, student_id, skill_id, recorded_on, uploaded_at, upload_status, storage_path, drill, restricted, restricted_reason, ' +
  'skills(name), students(display_name), assessments(id, rubric_version_id, scores, status, feedback, strengths, to_improve, next_goal, published_at)';
