const db = supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

const META = { nota: 80, revisar: 65, ppc: 85, liberadas: 90, cantidades: 90, evitables: 20 };

const CRITERIOS = [
  ['c_entrega', 'Entrega a tiempo', '¿llegó a tiempo?'],
  ['c_cronograma', 'Cronograma', '¿toca en estas 2 semanas?'],
  ['c_secuencia', 'Secuencia', '¿ya está lo que va antes?'],
  ['c_cantidad', 'Cantidad realista', '¿cabe en el rendimiento?'],
  ['c_recursos', 'Recursos', '¿cuadrilla y equipo completos?'],
  ['c_anticipacion', 'Anticipación', '¿se pidió a tiempo?'],
];

const h = valor => String(valor ?? '').replace(/[&<>"']/g, c => `&#${c.charCodeAt(0)};`);

const pct = (parte, total) => (Number(total) ? Math.round((100 * Number(parte)) / Number(total)) : null);

const suma = (lista, campo) => lista.reduce((total, fila) => total + Number(fila[campo] ?? 0), 0);

const dia = texto => new Date(`${texto}T00:00:00`);

const fecha = texto => dia(texto).toLocaleDateString('es-EC', { day: 'numeric', month: 'short' });

const periodo = inicio => {
  const fin = dia(inicio);
  fin.setDate(fin.getDate() + 11);
  return `${fecha(inicio)} al ${fin.toLocaleDateString('es-EC', { day: 'numeric', month: 'short' })}`;
};

const numero = valor => Number(valor).toLocaleString('es-EC', { maximumFractionDigits: 2 });

const nivel = nota =>
  nota >= META.nota ? ['Buen plan', 'ok'] : nota >= META.revisar ? ['Revisar', 'alerta'] : ['Rehacer', 'mal'];

const lectura = plan => {
  if (!plan) return '';
  if (pct(plan.cumplidas, plan.tareas) >= META.ppc) {
    return plan.nota >= META.nota ? 'Éxito: se repite y se reconoce' : 'Suerte o sobreesfuerzo: revisar el costo';
  }
  return Number(plan.externas) > Number(plan.evitables)
    ? 'Causa externa: evidencia para reclamar'
    : 'Evitable: corregir la planificación';
};

async function leer(consulta) {
  const { data, error } = await consulta;
  if (error) throw error;
  return data;
}

function avisar(texto, tipo = 'mal') {
  const aviso = document.getElementById('aviso');
  aviso.textContent = texto;
  aviso.className = `aviso ${tipo}`;
  aviso.hidden = !texto;
  if (texto) aviso.scrollIntoView({ behavior: 'smooth', block: 'center' });
}

function fallo(error) {
  console.error(error);
  const sinConfigurar = SUPABASE_URL.includes('TU-PROYECTO') || SUPABASE_KEY.includes('PEGA-AQUI');
  avisar(sinConfigurar ? 'Falta poner la URL y la clave de Supabase en config.js.' : `No se pudo: ${error.message ?? error}`);
}
