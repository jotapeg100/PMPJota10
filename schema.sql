--
-- PostgreSQL database dump
--

\restrict fDVlTpgcH6ZDp1hLIRMLBSJ4U0u3v15FZocgA7uiyH7qVIO43CW7fdsDJFN5d2H

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.9

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: app_role; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.app_role AS ENUM (
    'pmp',
    'externo',
    'admin'
);


--
-- Name: attachment_kind; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.attachment_kind AS ENUM (
    'delivery',
    'conformity'
);


--
-- Name: conformity_channel; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.conformity_channel AS ENUM (
    'email',
    'whatsapp',
    'meeting',
    'portal',
    'other'
);


--
-- Name: deliverable_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.deliverable_status AS ENUM (
    'draft',
    'published',
    'conformed'
);


--
-- Name: delivery_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.delivery_status AS ENUM (
    'pending',
    'delivered',
    'conformed',
    'overdue'
);


--
-- Name: rag_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.rag_status AS ENUM (
    'green',
    'amber',
    'red',
    'gray'
);


--
-- Name: can_access_deliverable_evidence(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_access_deliverable_evidence(_user_id uuid, _deliverable_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.deliverables d
    WHERE d.id = _deliverable_id
      AND public.can_see_project(_user_id, d.project_id)
  );
$$;


--
-- Name: can_see_initiative(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_see_initiative(_user_id uuid, _initiative_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT public.has_role(_user_id,'admin') OR public.has_role(_user_id,'pmp') OR EXISTS (
    SELECT 1
    FROM public.projects p
    JOIN public.project_members pm ON pm.project_id = p.id
    WHERE p.initiative_id = _initiative_id
      AND pm.user_id = _user_id
      AND pm.visible = true
  );
$$;


--
-- Name: can_see_project(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_see_project(_user_id uuid, _project_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT public.has_role(_user_id,'pmp') OR EXISTS(
    SELECT 1 FROM public.project_members pm
    WHERE pm.user_id = _user_id AND pm.visible = true AND (
      pm.project_id = _project_id OR pm.project_id = (SELECT parent_id FROM public.projects WHERE id = _project_id)
    )
  );
$$;


--
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name, email)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email,'@',1)), NEW.email)
  ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email;
  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'externo') ON CONFLICT DO NOTHING;
  RETURN NEW;
END;
$$;


--
-- Name: has_role(uuid, public.app_role); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.has_role(_user_id uuid, _role public.app_role) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS(SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role);
$$;


--
-- Name: set_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END $$;


--
-- Name: validate_deliverable_conformed(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_deliverable_conformed() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
  has_evidence boolean;
BEGIN
  IF NEW.delivery_status = 'conformed' THEN
    SELECT EXISTS (
      SELECT 1 FROM public.conformities c
      WHERE c.deliverable_id = NEW.id
        AND (
          (c.message IS NOT NULL AND length(trim(c.message)) > 0)
          OR (c.external_link IS NOT NULL AND length(trim(c.external_link)) > 0)
          OR EXISTS (
            SELECT 1 FROM public.deliverable_attachments a
            WHERE a.conformity_id = c.id AND a.kind = 'conformity'
          )
        )
    ) INTO has_evidence;
    IF NOT has_evidence THEN
      RAISE EXCEPTION 'No se puede marcar como conformado sin evidencia (mensaje, link o archivo de conformidad)';
    END IF;
  END IF;
  RETURN NEW;
END $$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: areas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.areas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    description text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT auth.uid()
);


--
-- Name: client_contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.client_contacts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    client_id uuid NOT NULL,
    contact_email text,
    contact_first_name text,
    contact_last_name text,
    contact_role text,
    contact_area text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: clients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.clients (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    slug text NOT NULL,
    logo_url text,
    industry text,
    status text DEFAULT 'active'::text NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT auth.uid()
);


--
-- Name: cockpit_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cockpit_rules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    singleton boolean DEFAULT true NOT NULL,
    high_risk_score integer DEFAULT 6 NOT NULL,
    escalation_high_risks integer DEFAULT 2 NOT NULL,
    upcoming_days integer DEFAULT 14 NOT NULL,
    ask_conformity_days integer DEFAULT 7 NOT NULL,
    amber_on_upcoming boolean DEFAULT true NOT NULL,
    amber_on_delivered_pending boolean DEFAULT true NOT NULL,
    expand_relationship_on_delivered boolean DEFAULT true NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid
);


--
-- Name: conformities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.conformities (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    deliverable_id uuid NOT NULL,
    user_id uuid NOT NULL,
    comment text,
    signed_at timestamp with time zone DEFAULT now() NOT NULL,
    received_at timestamp with time zone,
    channel public.conformity_channel,
    client_contact text,
    message text,
    external_link text,
    is_closure_act boolean DEFAULT false NOT NULL,
    external_links text[] DEFAULT '{}'::text[] NOT NULL,
    received_date date,
    observations text,
    CONSTRAINT conformities_external_link_scheme CHECK (((external_link IS NULL) OR (external_link ~* '^https?://'::text)))
);


--
-- Name: deliverable_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deliverable_attachments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    deliverable_id uuid NOT NULL,
    conformity_id uuid,
    kind public.attachment_kind NOT NULL,
    storage_path text NOT NULL,
    file_name text NOT NULL,
    mime text,
    size_bytes bigint,
    uploaded_by uuid,
    uploaded_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: deliverable_status_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deliverable_status_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    deliverable_id uuid NOT NULL,
    previous_status public.delivery_status,
    new_status public.delivery_status NOT NULL,
    notes text,
    changed_by uuid DEFAULT auth.uid(),
    changed_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: deliverables; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deliverables (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    project_id uuid NOT NULL,
    title text NOT NULL,
    description text,
    status public.deliverable_status DEFAULT 'draft'::public.deliverable_status NOT NULL,
    due_date date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    delivered_at timestamp with time zone,
    delivery_notes text,
    delivery_link text,
    delivery_status public.delivery_status DEFAULT 'pending'::public.delivery_status NOT NULL,
    created_by uuid DEFAULT auth.uid(),
    committed_date date,
    effective_date date,
    delivery_links text[] DEFAULT '{}'::text[] NOT NULL,
    CONSTRAINT deliverables_delivery_link_scheme CHECK (((delivery_link IS NULL) OR (delivery_link ~* '^https?://'::text)))
);


--
-- Name: initiatives; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.initiatives (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    code text,
    name text NOT NULL,
    description text,
    owner_id uuid,
    area_id uuid,
    rag public.rag_status DEFAULT 'gray'::public.rag_status NOT NULL,
    start_date date,
    end_date date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    client_id uuid NOT NULL
);


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    display_name text,
    area_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    email text,
    area text
);


--
-- Name: project_members; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_members (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    project_id uuid NOT NULL,
    user_id uuid NOT NULL,
    visible boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: projects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.projects (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    initiative_id uuid,
    parent_id uuid,
    code text,
    name text NOT NULL,
    description text,
    area_id uuid,
    owner_id uuid,
    rag public.rag_status DEFAULT 'gray'::public.rag_status NOT NULL,
    start_date date,
    end_date date,
    progress integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: risks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.risks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    project_id uuid NOT NULL,
    title text NOT NULL,
    description text,
    probability smallint NOT NULL,
    impact smallint NOT NULL,
    score smallint GENERATED ALWAYS AS ((probability * impact)) STORED,
    mitigation text,
    external boolean DEFAULT false NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid DEFAULT auth.uid(),
    CONSTRAINT risks_impact_check CHECK (((impact >= 1) AND (impact <= 3))),
    CONSTRAINT risks_probability_check CHECK (((probability >= 1) AND (probability <= 3)))
);


--
-- Name: user_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_roles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    role public.app_role NOT NULL
);


--
-- Name: areas areas_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.areas
    ADD CONSTRAINT areas_name_key UNIQUE (name);


--
-- Name: areas areas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.areas
    ADD CONSTRAINT areas_pkey PRIMARY KEY (id);


--
-- Name: client_contacts client_contacts_client_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_contacts
    ADD CONSTRAINT client_contacts_client_id_key UNIQUE (client_id);


--
-- Name: client_contacts client_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_contacts
    ADD CONSTRAINT client_contacts_pkey PRIMARY KEY (id);


--
-- Name: clients clients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_pkey PRIMARY KEY (id);


--
-- Name: clients clients_slug_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_slug_key UNIQUE (slug);


--
-- Name: cockpit_rules cockpit_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cockpit_rules
    ADD CONSTRAINT cockpit_rules_pkey PRIMARY KEY (id);


--
-- Name: cockpit_rules cockpit_rules_singleton_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cockpit_rules
    ADD CONSTRAINT cockpit_rules_singleton_key UNIQUE (singleton);


--
-- Name: conformities conformities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conformities
    ADD CONSTRAINT conformities_pkey PRIMARY KEY (id);


--
-- Name: deliverable_attachments deliverable_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deliverable_attachments
    ADD CONSTRAINT deliverable_attachments_pkey PRIMARY KEY (id);


--
-- Name: deliverable_status_history deliverable_status_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deliverable_status_history
    ADD CONSTRAINT deliverable_status_history_pkey PRIMARY KEY (id);


--
-- Name: deliverables deliverables_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deliverables
    ADD CONSTRAINT deliverables_pkey PRIMARY KEY (id);


--
-- Name: initiatives initiatives_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.initiatives
    ADD CONSTRAINT initiatives_code_key UNIQUE (code);


--
-- Name: initiatives initiatives_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.initiatives
    ADD CONSTRAINT initiatives_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: project_members project_members_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_members
    ADD CONSTRAINT project_members_pkey PRIMARY KEY (id);


--
-- Name: project_members project_members_project_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_members
    ADD CONSTRAINT project_members_project_id_user_id_key UNIQUE (project_id, user_id);


--
-- Name: projects projects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_pkey PRIMARY KEY (id);


--
-- Name: risks risks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.risks
    ADD CONSTRAINT risks_pkey PRIMARY KEY (id);


--
-- Name: user_roles user_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_pkey PRIMARY KEY (id);


--
-- Name: user_roles user_roles_user_id_role_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_user_id_role_key UNIQUE (user_id, role);


--
-- Name: conformities_deliverable_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX conformities_deliverable_idx ON public.conformities USING btree (deliverable_id);


--
-- Name: deliverable_attachments_conformity_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deliverable_attachments_conformity_idx ON public.deliverable_attachments USING btree (conformity_id);


--
-- Name: deliverable_attachments_deliverable_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deliverable_attachments_deliverable_idx ON public.deliverable_attachments USING btree (deliverable_id);


--
-- Name: deliverables_project_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deliverables_project_idx ON public.deliverables USING btree (project_id);


--
-- Name: initiatives_client_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX initiatives_client_idx ON public.initiatives USING btree (client_id);


--
-- Name: projects_initiative_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX projects_initiative_idx ON public.projects USING btree (initiative_id);


--
-- Name: projects_parent_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX projects_parent_idx ON public.projects USING btree (parent_id);


--
-- Name: risks_project_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX risks_project_idx ON public.risks USING btree (project_id);


--
-- Name: areas areas_updated; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER areas_updated BEFORE UPDATE ON public.areas FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: client_contacts client_contacts_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER client_contacts_set_updated_at BEFORE UPDATE ON public.client_contacts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: clients clients_updated; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER clients_updated BEFORE UPDATE ON public.clients FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: deliverables deliverables_updated; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER deliverables_updated BEFORE UPDATE ON public.deliverables FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: deliverables deliverables_validate_conformed; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER deliverables_validate_conformed BEFORE INSERT OR UPDATE OF delivery_status ON public.deliverables FOR EACH ROW EXECUTE FUNCTION public.validate_deliverable_conformed();


--
-- Name: initiatives initiatives_updated; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER initiatives_updated BEFORE UPDATE ON public.initiatives FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: profiles profiles_updated; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER profiles_updated BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: projects projects_updated; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER projects_updated BEFORE UPDATE ON public.projects FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: risks risks_updated; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER risks_updated BEFORE UPDATE ON public.risks FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: cockpit_rules trg_cockpit_rules_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_cockpit_rules_updated_at BEFORE UPDATE ON public.cockpit_rules FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: deliverable_status_history update_deliverable_status_history_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_deliverable_status_history_updated_at BEFORE UPDATE ON public.deliverable_status_history FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: client_contacts client_contacts_client_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_contacts
    ADD CONSTRAINT client_contacts_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE CASCADE;


--
-- Name: cockpit_rules cockpit_rules_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cockpit_rules
    ADD CONSTRAINT cockpit_rules_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: conformities conformities_deliverable_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conformities
    ADD CONSTRAINT conformities_deliverable_id_fkey FOREIGN KEY (deliverable_id) REFERENCES public.deliverables(id) ON DELETE CASCADE;


--
-- Name: conformities conformities_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conformities
    ADD CONSTRAINT conformities_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: deliverable_attachments deliverable_attachments_conformity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deliverable_attachments
    ADD CONSTRAINT deliverable_attachments_conformity_id_fkey FOREIGN KEY (conformity_id) REFERENCES public.conformities(id) ON DELETE CASCADE;


--
-- Name: deliverable_attachments deliverable_attachments_deliverable_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deliverable_attachments
    ADD CONSTRAINT deliverable_attachments_deliverable_id_fkey FOREIGN KEY (deliverable_id) REFERENCES public.deliverables(id) ON DELETE CASCADE;


--
-- Name: deliverable_attachments deliverable_attachments_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deliverable_attachments
    ADD CONSTRAINT deliverable_attachments_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: deliverable_status_history deliverable_status_history_changed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deliverable_status_history
    ADD CONSTRAINT deliverable_status_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: deliverable_status_history deliverable_status_history_deliverable_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deliverable_status_history
    ADD CONSTRAINT deliverable_status_history_deliverable_id_fkey FOREIGN KEY (deliverable_id) REFERENCES public.deliverables(id) ON DELETE CASCADE;


--
-- Name: deliverables deliverables_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deliverables
    ADD CONSTRAINT deliverables_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: initiatives initiatives_area_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.initiatives
    ADD CONSTRAINT initiatives_area_id_fkey FOREIGN KEY (area_id) REFERENCES public.areas(id) ON DELETE SET NULL;


--
-- Name: initiatives initiatives_client_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.initiatives
    ADD CONSTRAINT initiatives_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE RESTRICT;


--
-- Name: initiatives initiatives_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.initiatives
    ADD CONSTRAINT initiatives_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: profiles profiles_area_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_area_fk FOREIGN KEY (area_id) REFERENCES public.areas(id) ON DELETE SET NULL;


--
-- Name: profiles profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: project_members project_members_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_members
    ADD CONSTRAINT project_members_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: project_members project_members_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_members
    ADD CONSTRAINT project_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: projects projects_area_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_area_id_fkey FOREIGN KEY (area_id) REFERENCES public.areas(id) ON DELETE SET NULL;


--
-- Name: projects projects_initiative_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_initiative_id_fkey FOREIGN KEY (initiative_id) REFERENCES public.initiatives(id) ON DELETE CASCADE;


--
-- Name: projects projects_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: projects projects_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: risks risks_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.risks
    ADD CONSTRAINT risks_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: user_roles user_roles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: deliverable_status_history Staff can insert status history; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Staff can insert status history" ON public.deliverable_status_history FOR INSERT WITH CHECK ((public.has_role(auth.uid(), 'admin'::public.app_role) OR public.has_role(auth.uid(), 'pmp'::public.app_role)));


--
-- Name: deliverable_status_history Users can read history for visible deliverables; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can read history for visible deliverables" ON public.deliverable_status_history FOR SELECT TO authenticated USING ((public.has_role(auth.uid(), 'admin'::public.app_role) OR public.has_role(auth.uid(), 'pmp'::public.app_role) OR (EXISTS ( SELECT 1
   FROM public.deliverables d
  WHERE ((d.id = deliverable_status_history.deliverable_id) AND public.can_see_project(auth.uid(), d.project_id))))));


--
-- Name: areas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.areas ENABLE ROW LEVEL SECURITY;

--
-- Name: areas areas admin all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "areas admin all" ON public.areas TO authenticated USING (public.has_role(auth.uid(), 'admin'::public.app_role)) WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));


--
-- Name: areas areas pmp delete own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "areas pmp delete own" ON public.areas FOR DELETE TO authenticated USING ((public.has_role(auth.uid(), 'pmp'::public.app_role) AND ((created_by IS NULL) OR (created_by = auth.uid()))));


--
-- Name: areas areas pmp insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "areas pmp insert" ON public.areas FOR INSERT TO authenticated WITH CHECK (public.has_role(auth.uid(), 'pmp'::public.app_role));


--
-- Name: areas areas pmp update own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "areas pmp update own" ON public.areas FOR UPDATE TO authenticated USING ((public.has_role(auth.uid(), 'pmp'::public.app_role) AND ((created_by IS NULL) OR (created_by = auth.uid())))) WITH CHECK ((public.has_role(auth.uid(), 'pmp'::public.app_role) AND ((created_by IS NULL) OR (created_by = auth.uid()))));


--
-- Name: areas areas select all auth; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "areas select all auth" ON public.areas FOR SELECT TO authenticated USING (true);


--
-- Name: deliverable_attachments attachments delete pmp or uploader; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "attachments delete pmp or uploader" ON public.deliverable_attachments FOR DELETE USING ((public.has_role(auth.uid(), 'pmp'::public.app_role) OR public.has_role(auth.uid(), 'admin'::public.app_role) OR ((uploaded_by = auth.uid()) AND (EXISTS ( SELECT 1
   FROM public.deliverables d
  WHERE ((d.id = deliverable_attachments.deliverable_id) AND public.can_see_project(auth.uid(), d.project_id) AND (d.status = ANY (ARRAY['published'::public.deliverable_status, 'conformed'::public.deliverable_status]))))))));


--
-- Name: deliverable_attachments attachments insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "attachments insert" ON public.deliverable_attachments FOR INSERT WITH CHECK ((public.has_role(auth.uid(), 'pmp'::public.app_role) OR public.has_role(auth.uid(), 'admin'::public.app_role) OR (EXISTS ( SELECT 1
   FROM public.deliverables d
  WHERE ((d.id = deliverable_attachments.deliverable_id) AND public.can_see_project(auth.uid(), d.project_id) AND (d.status = ANY (ARRAY['published'::public.deliverable_status, 'conformed'::public.deliverable_status])))))));


--
-- Name: deliverable_attachments attachments select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "attachments select" ON public.deliverable_attachments FOR SELECT USING ((public.has_role(auth.uid(), 'pmp'::public.app_role) OR public.has_role(auth.uid(), 'admin'::public.app_role) OR (EXISTS ( SELECT 1
   FROM public.deliverables d
  WHERE ((d.id = deliverable_attachments.deliverable_id) AND public.can_see_project(auth.uid(), d.project_id) AND ((d.status)::text = ANY (ARRAY['published'::text, 'conformed'::text])))))));


--
-- Name: deliverable_attachments attachments update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "attachments update" ON public.deliverable_attachments FOR UPDATE USING ((public.has_role(auth.uid(), 'pmp'::public.app_role) OR public.has_role(auth.uid(), 'admin'::public.app_role) OR ((uploaded_by = auth.uid()) AND (EXISTS ( SELECT 1
   FROM public.deliverables d
  WHERE ((d.id = deliverable_attachments.deliverable_id) AND public.can_see_project(auth.uid(), d.project_id) AND (d.status = ANY (ARRAY['published'::public.deliverable_status, 'conformed'::public.deliverable_status])))))))) WITH CHECK ((public.has_role(auth.uid(), 'pmp'::public.app_role) OR public.has_role(auth.uid(), 'admin'::public.app_role) OR ((uploaded_by = auth.uid()) AND (EXISTS ( SELECT 1
   FROM public.deliverables d
  WHERE ((d.id = deliverable_attachments.deliverable_id) AND public.can_see_project(auth.uid(), d.project_id) AND (d.status = ANY (ARRAY['published'::public.deliverable_status, 'conformed'::public.deliverable_status]))))))));


--
-- Name: client_contacts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.client_contacts ENABLE ROW LEVEL SECURITY;

--
-- Name: client_contacts client_contacts staff all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "client_contacts staff all" ON public.client_contacts TO authenticated USING ((public.has_role(auth.uid(), 'admin'::public.app_role) OR public.has_role(auth.uid(), 'pmp'::public.app_role))) WITH CHECK ((public.has_role(auth.uid(), 'admin'::public.app_role) OR public.has_role(auth.uid(), 'pmp'::public.app_role)));


--
-- Name: clients; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;

--
-- Name: clients clients admin all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "clients admin all" ON public.clients USING (public.has_role(auth.uid(), 'admin'::public.app_role)) WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));


--
-- Name: clients clients pmp delete own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "clients pmp delete own" ON public.clients FOR DELETE TO authenticated USING ((public.has_role(auth.uid(), 'pmp'::public.app_role) AND ((created_by IS NULL) OR (created_by = auth.uid()))));


--
-- Name: clients clients pmp insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "clients pmp insert" ON public.clients FOR INSERT TO authenticated WITH CHECK (public.has_role(auth.uid(), 'pmp'::public.app_role));


--
-- Name: clients clients pmp update own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "clients pmp update own" ON public.clients FOR UPDATE TO authenticated USING ((public.has_role(auth.uid(), 'pmp'::public.app_role) AND ((created_by IS NULL) OR (created_by = auth.uid())))) WITH CHECK ((public.has_role(auth.uid(), 'pmp'::public.app_role) AND ((created_by IS NULL) OR (created_by = auth.uid()))));


--
-- Name: clients clients select scoped; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "clients select scoped" ON public.clients FOR SELECT TO authenticated USING ((public.has_role(auth.uid(), 'pmp'::public.app_role) OR public.has_role(auth.uid(), 'admin'::public.app_role) OR (EXISTS ( SELECT 1
   FROM public.initiatives i
  WHERE ((i.client_id = clients.id) AND public.can_see_initiative(auth.uid(), i.id))))));


--
-- Name: cockpit_rules; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cockpit_rules ENABLE ROW LEVEL SECURITY;

--
-- Name: cockpit_rules cockpit_rules admin delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "cockpit_rules admin delete" ON public.cockpit_rules FOR DELETE TO authenticated USING (public.has_role(auth.uid(), 'admin'::public.app_role));


--
-- Name: cockpit_rules cockpit_rules admin insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "cockpit_rules admin insert" ON public.cockpit_rules FOR INSERT TO authenticated WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));


--
-- Name: cockpit_rules cockpit_rules admin update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "cockpit_rules admin update" ON public.cockpit_rules FOR UPDATE TO authenticated USING (public.has_role(auth.uid(), 'admin'::public.app_role)) WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));


--
-- Name: cockpit_rules cockpit_rules read all authenticated; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "cockpit_rules read all authenticated" ON public.cockpit_rules FOR SELECT TO authenticated USING (true);


--
-- Name: conformities; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.conformities ENABLE ROW LEVEL SECURITY;

--
-- Name: conformities conformities delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "conformities delete" ON public.conformities FOR DELETE TO authenticated USING (public.has_role(auth.uid(), 'pmp'::public.app_role));


--
-- Name: conformities conformities insert self; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "conformities insert self" ON public.conformities FOR INSERT TO authenticated WITH CHECK (((user_id = auth.uid()) AND (EXISTS ( SELECT 1
   FROM public.deliverables d
  WHERE ((d.id = conformities.deliverable_id) AND (d.status = ANY (ARRAY['published'::public.deliverable_status, 'conformed'::public.deliverable_status])) AND (d.delivery_status = ANY (ARRAY['delivered'::public.delivery_status, 'conformed'::public.delivery_status])) AND (public.has_role(auth.uid(), 'admin'::public.app_role) OR public.can_see_project(auth.uid(), d.project_id)))))));


--
-- Name: conformities conformities select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "conformities select" ON public.conformities FOR SELECT TO authenticated USING ((public.has_role(auth.uid(), 'admin'::public.app_role) OR public.has_role(auth.uid(), 'pmp'::public.app_role) OR (user_id = auth.uid())));


--
-- Name: conformities conformities update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "conformities update" ON public.conformities FOR UPDATE TO authenticated USING (public.has_role(auth.uid(), 'pmp'::public.app_role)) WITH CHECK (public.has_role(auth.uid(), 'pmp'::public.app_role));


--
-- Name: deliverable_attachments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.deliverable_attachments ENABLE ROW LEVEL SECURITY;

--
-- Name: deliverable_status_history; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.deliverable_status_history ENABLE ROW LEVEL SECURITY;

--
-- Name: deliverables; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.deliverables ENABLE ROW LEVEL SECURITY;

--
-- Name: deliverables deliverables admin all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "deliverables admin all" ON public.deliverables TO authenticated USING (public.has_role(auth.uid(), 'admin'::public.app_role)) WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));


--
-- Name: deliverables deliverables pmp delete own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "deliverables pmp delete own" ON public.deliverables FOR DELETE TO authenticated USING ((public.has_role(auth.uid(), 'pmp'::public.app_role) AND ((created_by IS NULL) OR (created_by = auth.uid()))));


--
-- Name: deliverables deliverables pmp insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "deliverables pmp insert" ON public.deliverables FOR INSERT TO authenticated WITH CHECK (public.has_role(auth.uid(), 'pmp'::public.app_role));


--
-- Name: deliverables deliverables pmp update own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "deliverables pmp update own" ON public.deliverables FOR UPDATE TO authenticated USING ((public.has_role(auth.uid(), 'pmp'::public.app_role) AND ((created_by IS NULL) OR (created_by = auth.uid())))) WITH CHECK ((public.has_role(auth.uid(), 'pmp'::public.app_role) AND ((created_by IS NULL) OR (created_by = auth.uid()))));


--
-- Name: deliverables deliverables select scoped; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "deliverables select scoped" ON public.deliverables FOR SELECT TO authenticated USING ((public.has_role(auth.uid(), 'admin'::public.app_role) OR public.can_see_project(auth.uid(), project_id)));


--
-- Name: initiatives; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.initiatives ENABLE ROW LEVEL SECURITY;

--
-- Name: initiatives initiatives admin all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "initiatives admin all" ON public.initiatives USING (public.has_role(auth.uid(), 'admin'::public.app_role)) WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));


--
-- Name: initiatives initiatives pmp delete own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "initiatives pmp delete own" ON public.initiatives FOR DELETE TO authenticated USING ((public.has_role(auth.uid(), 'pmp'::public.app_role) AND ((owner_id IS NULL) OR (owner_id = auth.uid()))));


--
-- Name: initiatives initiatives pmp insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "initiatives pmp insert" ON public.initiatives FOR INSERT TO authenticated WITH CHECK (public.has_role(auth.uid(), 'pmp'::public.app_role));


--
-- Name: initiatives initiatives pmp update own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "initiatives pmp update own" ON public.initiatives FOR UPDATE TO authenticated USING ((public.has_role(auth.uid(), 'pmp'::public.app_role) AND ((owner_id IS NULL) OR (owner_id = auth.uid())))) WITH CHECK ((public.has_role(auth.uid(), 'pmp'::public.app_role) AND ((owner_id IS NULL) OR (owner_id = auth.uid()))));


--
-- Name: initiatives initiatives select scoped; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "initiatives select scoped" ON public.initiatives FOR SELECT TO authenticated USING ((public.has_role(auth.uid(), 'admin'::public.app_role) OR public.can_see_initiative(auth.uid(), id)));


--
-- Name: project_members members_delete_staff; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY members_delete_staff ON public.project_members FOR DELETE TO authenticated USING ((public.has_role(auth.uid(), 'admin'::public.app_role) OR public.has_role(auth.uid(), 'pmp'::public.app_role)));


--
-- Name: project_members members_manage_staff; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY members_manage_staff ON public.project_members FOR INSERT TO authenticated WITH CHECK ((public.has_role(auth.uid(), 'admin'::public.app_role) OR public.has_role(auth.uid(), 'pmp'::public.app_role)));


--
-- Name: project_members members_select_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY members_select_admin ON public.project_members FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'::public.app_role));


--
-- Name: project_members members_select_pmp_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY members_select_pmp_all ON public.project_members FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'pmp'::public.app_role));


--
-- Name: project_members members_select_self; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY members_select_self ON public.project_members FOR SELECT TO authenticated USING ((auth.uid() = user_id));


--
-- Name: project_members members_update_staff; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY members_update_staff ON public.project_members FOR UPDATE TO authenticated USING ((public.has_role(auth.uid(), 'admin'::public.app_role) OR public.has_role(auth.uid(), 'pmp'::public.app_role))) WITH CHECK ((public.has_role(auth.uid(), 'admin'::public.app_role) OR public.has_role(auth.uid(), 'pmp'::public.app_role)));


--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles profiles select self or staff; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "profiles select self or staff" ON public.profiles FOR SELECT TO authenticated USING (((auth.uid() = id) OR public.has_role(auth.uid(), 'pmp'::public.app_role) OR public.has_role(auth.uid(), 'admin'::public.app_role)));


--
-- Name: profiles profiles update self or admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "profiles update self or admin" ON public.profiles FOR UPDATE TO authenticated USING (((auth.uid() = id) OR public.has_role(auth.uid(), 'admin'::public.app_role))) WITH CHECK (((auth.uid() = id) OR public.has_role(auth.uid(), 'admin'::public.app_role)));


--
-- Name: project_members; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.project_members ENABLE ROW LEVEL SECURITY;

--
-- Name: projects; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;

--
-- Name: projects projects admin all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "projects admin all" ON public.projects USING (public.has_role(auth.uid(), 'admin'::public.app_role)) WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));


--
-- Name: projects projects pmp delete own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "projects pmp delete own" ON public.projects FOR DELETE TO authenticated USING ((public.has_role(auth.uid(), 'pmp'::public.app_role) AND ((owner_id IS NULL) OR (owner_id = auth.uid()))));


--
-- Name: projects projects pmp insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "projects pmp insert" ON public.projects FOR INSERT TO authenticated WITH CHECK (public.has_role(auth.uid(), 'pmp'::public.app_role));


--
-- Name: projects projects pmp update own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "projects pmp update own" ON public.projects FOR UPDATE TO authenticated USING ((public.has_role(auth.uid(), 'pmp'::public.app_role) AND ((owner_id IS NULL) OR (owner_id = auth.uid())))) WITH CHECK ((public.has_role(auth.uid(), 'pmp'::public.app_role) AND ((owner_id IS NULL) OR (owner_id = auth.uid()))));


--
-- Name: projects projects select scoped; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "projects select scoped" ON public.projects FOR SELECT TO authenticated USING ((public.has_role(auth.uid(), 'admin'::public.app_role) OR public.can_see_project(auth.uid(), id)));


--
-- Name: risks; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.risks ENABLE ROW LEVEL SECURITY;

--
-- Name: risks risks admin all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "risks admin all" ON public.risks USING (public.has_role(auth.uid(), 'admin'::public.app_role)) WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));


--
-- Name: risks risks pmp delete own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "risks pmp delete own" ON public.risks FOR DELETE TO authenticated USING ((public.has_role(auth.uid(), 'pmp'::public.app_role) AND ((created_by IS NULL) OR (created_by = auth.uid()))));


--
-- Name: risks risks pmp insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "risks pmp insert" ON public.risks FOR INSERT TO authenticated WITH CHECK (public.has_role(auth.uid(), 'pmp'::public.app_role));


--
-- Name: risks risks pmp update own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "risks pmp update own" ON public.risks FOR UPDATE TO authenticated USING ((public.has_role(auth.uid(), 'pmp'::public.app_role) AND ((created_by IS NULL) OR (created_by = auth.uid())))) WITH CHECK ((public.has_role(auth.uid(), 'pmp'::public.app_role) AND ((created_by IS NULL) OR (created_by = auth.uid()))));


--
-- Name: risks risks select scoped; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "risks select scoped" ON public.risks FOR SELECT TO authenticated USING ((public.has_role(auth.uid(), 'admin'::public.app_role) OR public.can_see_project(auth.uid(), project_id)));


--
-- Name: user_roles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

--
-- Name: user_roles user_roles admin manage; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "user_roles admin manage" ON public.user_roles TO authenticated USING (public.has_role(auth.uid(), 'admin'::public.app_role)) WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));


--
-- Name: user_roles user_roles admin select all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "user_roles admin select all" ON public.user_roles FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'::public.app_role));


--
-- Name: user_roles user_roles select self; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "user_roles select self" ON public.user_roles FOR SELECT TO authenticated USING ((auth.uid() = user_id));


--
-- PostgreSQL database dump complete
--

\unrestrict fDVlTpgcH6ZDp1hLIRMLBSJ4U0u3v15FZocgA7uiyH7qVIO43CW7fdsDJFN5d2H

