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
  status: 'draft' | 'published';
  feedback: string | null;
  next_goal: string | null;
  published_at: string | null;
}

export interface Clip {
  id: string;
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
