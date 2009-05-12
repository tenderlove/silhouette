
#include <time.h>
#ifdef HAVE_SYS_TIMES_H
#include <sys/times.h>
#endif
#include <unistd.h>
#include <ruby.h>
#include <node.h>
#include <st.h>
#include <limits.h>

static FILE *pro_file;
static struct timeval global_tv;
static int profiling_pid;
static st_table *method_tbl;
static st_table *file_tbl;
static char *time_magic = "@";
static char *start_magic = "!";
static char *binary_magic = "<>";
static char *method_magic = "&";
static char *file_magic = "*";
static char *call_magic = "c";
static char *return_magic = "r";
static char *line_magic = "l";
static char *null_ptr = "\0";
static int profiler_cost = 0;
static char *method_size_magic = "(";
static char *file_size_magic = ")";
static int method_idx_size = 0;
static int file_idx_size = 0;
static int emit_lines = 0;

#define PER_TIME 10
#define HASH_SIZE 128

#define CLOCK clock()
#define STR(x) RSTRING(x)->ptr

static void
extprof_event_hook(rb_event_t event, NODE *node,
	VALUE self, ID mid, VALUE in_klass) {

    static int profiling = 0;
	static char *method, *s_klass;
	static char *kind, *file;
	static int line;
	static VALUE klass;
	static char method_ent[1024];
	static char file_ent[1024];
	static int method_idx = 1;
	static int file_idx = 1;
	unsigned int current_clock = CLOCK;
	unsigned int i, j, m_idx, f_idx, size;
	unsigned short s_m_idx, s_f_idx;

	/* If we've forked, dont profile anymore. */
	if(getpid() != profiling_pid) {
		return;
	}

    if (mid == ID_ALLOCATOR) return;
    if (profiling) return;
    profiling++;
    
    if(!mid) {
	    method = "(main)";
    } else {
    	method = rb_id2name(mid);
    	if(!method) {
    		method = "<undefined>";
    	}
	}
    
	if(rb_obj_is_kind_of(self, rb_cModule)) {
	    kind = ".";
	    klass = rb_class_name(self);
	    i = RSTRING(klass)->len;
	    s_klass = RSTRING(klass)->ptr;
	    memcpy(method_ent, s_klass, i);
	    *(method_ent + i) = '.';
	} else {
	    kind = "#";
	    if(!in_klass) {
	        in_klass = rb_cObject;
	    }
	    klass = rb_class_name(in_klass);
	    i = RSTRING(klass)->len;
	    s_klass = RSTRING(klass)->ptr;
	    memcpy(method_ent, s_klass, i);
	    *(method_ent + i) = '#';
	}
	
	j = strlen(method);
	
	memcpy(method_ent + i + 1, method, j);
	*(method_ent + i + 1 + j) = 0;
		
	// sprintf(method_ent, "%s%s%s", s_klass, kind, method);
	if(!st_lookup(method_tbl, (st_data_t)method_ent, (st_data_t*)&m_idx)) {
	    m_idx = ++method_idx;
	    if(method_idx > USHRT_MAX) {
	        method_idx_size = 1;
	        fwrite(&method_size_magic, 1, 1, pro_file);
	    }
	    st_insert(method_tbl, (st_data_t)method_ent, method_idx);
	    fwrite(method_magic, 1, 1, pro_file);
	    size = 4 + RSTRING(klass)->len + 4 + j;
	    fwrite(&size, 4, 1, pro_file);
	    fwrite(&method_idx, 4, 1, pro_file);
	    fwrite(RSTRING(klass)->ptr, RSTRING(klass)->len, 1, pro_file);
	    fwrite(null_ptr, 1, 1, pro_file);
	    fwrite(kind, 1, 1, pro_file);
	    fwrite(null_ptr, 1, 1, pro_file);
	    fwrite(method, j, 1, pro_file);
	    fwrite(null_ptr, 1, 1, pro_file);
	    // fprintf(pro_file, "& %d %s %s %s\n", method_idx, s_klass, kind, method);
	}
	
	if(node) {
	    file = node->nd_file;
	    line = nd_line(node);
	    // printf("%s:%d\n", file, line);
	    if(!st_lookup(file_tbl, (st_data_t)(node->nd_file), (st_data_t*)&f_idx)) {
    	    f_idx = ++file_idx;
    	    if(file_idx > USHRT_MAX) {
    	        file_idx_size = 1;
    	        fwrite(&file_size_magic, 1, 1, pro_file);
    	    }
    	    st_insert(file_tbl, (st_data_t)(node->nd_file), file_idx);
    	    fwrite(file_magic, 1, 1, pro_file);
    	    j = strlen(node->nd_file);
    	    size = j + 5;
    	    fwrite(&size, 4, 1, pro_file);
    	    fwrite(&file_idx, 4, 1, pro_file);
    	    fwrite(node->nd_file, j + 1, 1, pro_file);
    	    //fprintf(pro_file, "* %d %s\n", file_idx, node->nd_file);
    	}
    } else {
        file = "<unknown>";
        line = 0;
        f_idx = 0;
	}
#define PL_S(type) fprintf(pro_file, #type " %x %d %d %d\n", (int)rb_thread_current(), \
            m_idx, f_idx, CLOCK);
#define PL(type) fprintf(pro_file, #type " %x %s %s %s %d\n", (int)rb_thread_current(), \
		    STR(rb_class_name(klass)), kind, method, CLOCK)
#define PL_EXT(type) fprintf(pro_file, #type " %x %s %x %s %s %s %d %f\n", (int)rb_thread_current(), \
		    STR(rb_class_name(klass)), (int)self, kind, method, file, line, CLOCK)
    
    switch(event) {
    case RUBY_EVENT_LINE:
        fwrite(line_magic, 1, 1, pro_file);
        goto output;
    case RUBY_EVENT_RETURN:
    case RUBY_EVENT_C_RETURN:
    	fwrite(return_magic, 1, 1, pro_file);
    	goto output;	
	case RUBY_EVENT_CALL:
	case RUBY_EVENT_C_CALL:
	    fwrite(call_magic, 1, 1, pro_file);
output:
	    j = (int)rb_thread_current();
	    fwrite(&j, 4, 1, pro_file);
	    
	    if(method_idx_size) {
	        fwrite(&m_idx, sizeof(m_idx), 1, pro_file);
        } else {
            s_m_idx = m_idx;
            fwrite(&s_m_idx, sizeof(s_m_idx), 1, pro_file);
        }
        
        if(file_idx_size) {
	        fwrite(&f_idx, sizeof(f_idx), 1, pro_file);
	    } else {
	        s_f_idx = f_idx;
	        fwrite(&s_f_idx, sizeof(s_f_idx), 1, pro_file);
	    }
	    
	    if(node) {
	        j = nd_line(node);
        } else {
            j = 0;
        }
	    fwrite(&j, 4, 1, pro_file);
	    fwrite(&current_clock, 4, 1, pro_file);
		break;
    }
done:
    profiler_cost = profiler_cost + (CLOCK - current_clock);
    profiling--;
}

static VALUE extprof_start(int argc, VALUE *argv, VALUE self) {
	struct timeval tv;
	char path[1024];
	int size, i, mask;
	
	mask = -1;
	
	emit_lines = 0;

	if(argc == 0) {
		pro_file = fopen("silhouette.out","w");
	} else {
	    if(rb_obj_is_kind_of(argv[0], rb_cIO)) {
	        pro_file = fdopen(NUM2INT(
	            rb_funcall(argv[0], rb_intern("fileno"), 0)), "w");
	    } else {
		    StringValue(argv[0]);
		    pro_file = fopen(STR(argv[0]), "w");
	    }
		if(argc == 2) {
		    if(argv[1] == Qfalse || argv[1] == Qtrue) {
    		    emit_lines = RTEST(argv[1]);		        
		    } else {
		        mask = NUM2INT(argv[1]);
		    }
		}
	}

	profiling_pid = getpid();

	method_tbl = st_init_strtable_with_size(HASH_SIZE);
	file_tbl = st_init_strtable_with_size(HASH_SIZE);

	getcwd(path, 1023);
	size = strlen(path);
	path[size] = 0;
	
	fwrite(binary_magic, 2 ,1 , pro_file);
	fwrite(start_magic, 1, 1, pro_file);
	i = size + 9;
	fwrite(&i, 4, 1, pro_file);
	fwrite(path, size + 1, 1, pro_file);
	i = CLOCKS_PER_SEC;
	fwrite(&i, 4, 1, pro_file);
	i = CLOCK;
	fwrite(&i, 4, 1, pro_file);
	// fprintf(pro_file, "! %s %d %d\n", getcwd(path, 1023), getpid(),
	//    CLOCKS_PER_SEC);
	/*
	gettimeofday(&tv, NULL);
	fprintf(pro_file, "@ %d %d %d\n", (int)tv.tv_sec, 
	    (int)tv.tv_usec, CLOCK);
	 */
	if(mask == -1) {
    	mask = RUBY_EVENT_CALL | RUBY_EVENT_RETURN |
            RUBY_EVENT_C_CALL | RUBY_EVENT_C_RETURN;
    
        if(emit_lines) {
            mask = mask | RUBY_EVENT_LINE;
        }
    }
    
    rb_add_event_hook(extprof_event_hook, mask);
	    
	return Qtrue;
}

static VALUE extprof_end(VALUE self) {
	struct timeval tv;
	int i;
    
	rb_remove_event_hook(extprof_event_hook);
	
	fwrite(time_magic, 1, 1, pro_file);
	i = CLOCK;
	fwrite(&i, 4, 1, pro_file);
	fwrite(&profiler_cost, 4, 1, pro_file);
	/*
	gettimeofday(&tv, NULL);
	fprintf(pro_file, "@ %d %d %d\n", (int)tv.tv_sec,
	    (int)tv.tv_usec, CLOCK);
	*/    
	fflush(pro_file);
	fclose(pro_file);
	return Qtrue;
}

void Init_silhouette_ext() {
	VALUE extprof;
	extprof = rb_define_module("Silhouette");
	rb_define_const(extprof, "CALL", INT2NUM(RUBY_EVENT_CALL | RUBY_EVENT_RETURN));
	rb_define_const(extprof, "C_CALL", INT2NUM(RUBY_EVENT_C_CALL | RUBY_EVENT_C_RETURN));
	rb_define_const(extprof, "LINE", INT2NUM(RUBY_EVENT_LINE));
	rb_define_const(extprof, "COVERAGE", INT2NUM(RUBY_EVENT_LINE | RUBY_EVENT_END));
	rb_define_const(extprof, "CALLS", INT2NUM(RUBY_EVENT_CALL | RUBY_EVENT_RETURN |
        RUBY_EVENT_C_CALL | RUBY_EVENT_C_RETURN));
    rb_define_const(extprof, "ALL", INT2NUM(RUBY_EVENT_ALL));
    	
	rb_define_singleton_method(extprof, "start_profile", extprof_start, -1);
	rb_define_singleton_method(extprof, "stop_profile", extprof_end, 0);
}

/* vim: set filetype=c ts=4 sw=4 noexpandtab : */
