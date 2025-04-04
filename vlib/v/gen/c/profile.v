module c

import v.ast

pub struct ProfileCounterMeta {
	fn_name   string
	vpc_name  string
	vpc_calls string
}

fn (mut g Gen) profile_fn(fn_decl ast.FnDecl) {
	if g.pref.profile_no_inline && fn_decl.attrs.contains('inline') {
		g.defer_profile_code = ''
		return
	}
	fn_name := fn_decl.name
	cfn_name := g.last_fn_c_name
	if fn_name.starts_with('time.vpc_now') || fn_name.starts_with('v.profile.') {
		g.defer_profile_code = ''
	} else {
		measure_fn_name := if g.pref.os == .macos { 'time__vpc_now_darwin' } else { 'time__vpc_now' }
		fn_profile_counter_name := 'vpc_${cfn_name}'
		fn_profile_counter_name_calls := '${fn_profile_counter_name}_calls'
		g.writeln('')
		should_restore_v__profile_enabled := g.pref.profile_fns.len > 0
			&& cfn_name in g.pref.profile_fns
		if should_restore_v__profile_enabled {
			$if trace_profile_fns ? {
				eprintln('> profile_fn | ${g.pref.profile_fns} | ${cfn_name}')
			}
			g.writeln('\tbool _prev_v__profile_enabled = v__profile_enabled;')
			g.writeln('\tv__profile_enabled = true;')
		}
		g.writeln('\tdouble _PROF_FN_START = ${measure_fn_name}();')
		g.writeln('\tdouble _PROF_PREV_MEASURED_TIME = prof_measured_time;')
		g.writeln('if(v__profile_enabled) { ${fn_profile_counter_name_calls}++; } // ${fn_name}')
		g.writeln('')
		g.defer_profile_code = '\tif(v__profile_enabled) { \n\t\tdouble _PROF_ELAPSED = ${measure_fn_name}() - _PROF_FN_START;\n'
		g.defer_profile_code += '\t\t${fn_profile_counter_name} += _PROF_ELAPSED;\n'
		g.defer_profile_code += '\t\t${fn_profile_counter_name}_only_current += _PROF_ELAPSED - (prof_measured_time - _PROF_PREV_MEASURED_TIME);\n'
		g.defer_profile_code += '\t\tprof_measured_time = _PROF_PREV_MEASURED_TIME + _PROF_ELAPSED;\n\t}'
		if should_restore_v__profile_enabled {
			g.defer_profile_code += '\n\t\tv__profile_enabled = _prev_v__profile_enabled;'
		}
		g.pcs_declarations.writeln('double ${fn_profile_counter_name} = 0.0; double ${fn_profile_counter_name}_only_current = 0.0; u64 ${fn_profile_counter_name_calls} = 0;')
		g.pcs << ProfileCounterMeta{
			fn_name:   cfn_name
			vpc_name:  fn_profile_counter_name
			vpc_calls: fn_profile_counter_name_calls
		}
	}
}

pub fn (mut g Gen) gen_vprint_profile_stats() {
	g.pcs_declarations.writeln('void vprint_profile_stats(){')
	fstring := '"%14llu %14.3fms %14.3fms %14.0fns %s \\n"'
	g.pcs_declarations.writeln('\tf64 f = 1.0;')
	if g.pref.os == .windows {
		// QueryPerformanceCounter() / QueryPerformanceFrequency()
		// https://learn.microsoft.com/en-us/windows/win32/sysinfo/acquiring-high-resolution-time-stamps
		g.pcs_declarations.writeln('\tu64 freq_time = 0;')
		g.pcs_declarations.writeln('\tQueryPerformanceFrequency(((voidptr)(&freq_time)));')
		g.pcs_declarations.writeln('\tf = (f64)1000000000.0/(f64)freq_time;')
	}
	if g.pref.profile_file == '-' {
		for pc_meta in g.pcs {
			g.pcs_declarations.writeln('\tif (${pc_meta.vpc_calls}) printf(${fstring}, ${pc_meta.vpc_calls}, (${pc_meta.vpc_name}*f)/1000000.0, (${pc_meta.vpc_name}_only_current*f)/1000000.0, (${pc_meta.vpc_name}*f)/${pc_meta.vpc_calls}, "${pc_meta.fn_name}" );')
		}
	} else {
		g.pcs_declarations.writeln('\tFILE * fp;')
		g.pcs_declarations.writeln('\tfp = fopen ("${g.pref.profile_file}", "w+");')
		for pc_meta in g.pcs {
			g.pcs_declarations.writeln('\tif (${pc_meta.vpc_calls}) fprintf(fp, ${fstring}, ${pc_meta.vpc_calls}, (${pc_meta.vpc_name}*f)/1000000.0, (${pc_meta.vpc_name}_only_current*f)/1000000.0, (${pc_meta.vpc_name}*f)/${pc_meta.vpc_calls}, "${pc_meta.fn_name}" );')
		}
		g.pcs_declarations.writeln('\tfclose(fp);')
	}
	g.pcs_declarations.writeln('}')
	g.pcs_declarations.writeln('')
	g.pcs_declarations.writeln('void vreset_profile_stats(){')
	for pc_meta in g.pcs {
		g.pcs_declarations.writeln('\t${pc_meta.vpc_calls} = 0;')
		g.pcs_declarations.writeln('\t${pc_meta.vpc_name} = 0.0;')
	}
	g.pcs_declarations.writeln('}')
	g.pcs_declarations.writeln('')

	g.pcs_declarations.writeln('void vprint_profile_stats_on_signal(int sig){')
	g.pcs_declarations.writeln('\texit(130);')
	g.pcs_declarations.writeln('}')
	g.pcs_declarations.writeln('')
}
