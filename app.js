const db = supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

const META = { nota: 80, revisar: 65, ppc: 85, liberadas: 90, cantidades: 90, evitables: 20 };

const CRITERIOS = [
  ['c_entrega', 'Entrega a tiempo', '¿Se entregó antes del viernes previo al inicio?'],
  ['c_cronograma', 'Cronograma', '¿El rubro corresponde a estas 2 semanas?'],
  ['c_secuencia', 'Secuencia previa', '¿Está terminado lo que va antes en la obra?'],
  ['c_cantidad', 'Cantidad realista', '¿Cabe en el rendimiento diario de la cuadrilla?'],
  ['c_recursos', 'Recursos y equipo', '¿La cuadrilla y equipos están 100% disponibles?'],
  ['c_anticipacion', 'Anticipación', '¿Los materiales fueron pedidos a tiempo?'],
];

const GLOSARIO_KPIS = {
  nota: {
    titulo: 'Nota del Plan (Tiempo 1)',
    subtitulo: 'Calidad de la planificación antes de empezar la obra',
    formula: 'Promedio de 6 criterios ponderados (0 a 100 puntos)',
    meta: '≥ 80 puntos (Buen plan)',
    queEs: 'Evalúa si el Lookahead de 2 semanas es confiable y ejecutable antes de que la cuadrilla empiece a trabajar. Evita salir al campo a improvisar.',
    comoSeCalcula: 'Tres criterios los audita el sistema solo (entrega oportuna, fecha según cronograma y cantidad no inflada respecto al rendimiento). Los otros tres los declara el supervisor (secuencia constructiva, cuadrilla/equipo completos y materiales pedidos con debida anticipación).',
    accion: 'Nota ≥ 80: Aprobar y ejecutar con confianza.<br>Nota 65 a 79: Revisar restricciones pendientes antes del lunes.<br>Nota < 65: Riesgo severo de pérdidas y paralización; rehacer el plan.',
  },
  liberadas: {
    titulo: 'Restricciones Liberadas (Tiempo 1)',
    subtitulo: 'Gestión proactiva de interferencias y permisos',
    formula: '(Restricciones resueltas ÷ Restricciones totales identificadas) × 100',
    meta: '≥ 90 % liberadas',
    queEs: 'Mide cuántas trabas (permisos ambientales, frentes entregados por el cliente, planos aprobados, compras críticas) se destrabaron antes del inicio.',
    comoSeCalcula: 'Si un supervisor identificó 10 restricciones y 9 ya están liberadas, el indicador es 90 %.',
    accion: 'Permite a la gerencia presionar a las áreas de soporte y al cliente antes de que los frentes queden paralizados con personal cobrando horas improductivas.',
  },
  ppc: {
    titulo: 'PPC · Porcentaje de Plan Cumplido (Tiempo 2)',
    subtitulo: 'Confiabilidad y cumplimiento de compromisos quincenales',
    formula: '(Rubros cumplidos al 100 % ÷ Rubros planificados) × 100',
    meta: '≥ 85 %',
    queEs: 'Es el indicador reina de Last Planner System. Mide la confiabilidad del equipo: si prometiste terminar 10 rubros en la quincena, ¿cuántos se completaron?',
    comoSeCalcula: 'Un rubro solo cuenta como cumplido si lo ejecutado real es mayor o igual a lo planificado. No hay "puntos por intentar".',
    accion: 'Si el PPC es alto con buena nota de plan: éxito metodológico sostenible.<br>Si el PPC es alto con nota baja: sobrecostos ocultos, horas extras excesivas o desorden operativo.<br>Si el PPC es bajo: analizar de inmediato las causas de no cumplimiento.',
  },
  cantidades: {
    titulo: 'Cumplimiento de Cantidades (Tiempo 2)',
    subtitulo: 'Valorización económica real vs. prevista',
    formula: 'Valor ejecutado en dólares ($) ÷ Valor planificado en dólares ($)',
    meta: '≥ 90 %',
    queEs: 'Mide el avance financiero en dinero de los rubros planificados en función de su precio unitario contractual.',
    comoSeCalcula: 'Suma de (cantidad ejecutada × precio unitario) sobre la suma de (cantidad planificada × precio unitario). No premia sobre-ejecutar rubros no planificados.',
    accion: 'Asegura que el flujo de caja y la facturación quincenal vayan alineados con el presupuesto proyectado.',
  },
  evitables: {
    titulo: 'Fallas Evitables (Tiempo 2)',
    subtitulo: 'Problemas internos de gestión del contratista',
    formula: '(Rubros fallados por cuadrilla, material o equipo ÷ Rubros totales) × 100',
    meta: '< 20 %',
    queEs: 'Identifica los incumplimientos que fueron 100 % responsabilidad interna de la empresa (la cuadrilla no rindió, faltaron herramientas, o el material no se despachó a tiempo).',
    comoSeCalcula: 'Fallas clasificadas bajo causa "evitable" en el cierre.',
    accion: 'Son las lecciones aprendidas directas para corregir internamente la logística y la supervisión de campo.',
  },
  externas: {
    titulo: 'Atrasos Externos Documentados (Sustento SDC)',
    subtitulo: 'Evidencia técnica irrefutable para reclamos y ampliaciones',
    formula: 'Suma de días de atraso por causas ajenas al contratista',
    meta: 'Documentación inmediata',
    queEs: 'Registra los días y frentes afectados por causas del cliente o fuerza mayor (lluvias extraordinarias, demora en respuesta de diseño, frentes no liberados por LUG).',
    comoSeCalcula: 'Días anotados por el supervisor con su causa externa y rubro afectado en el cierre quincenal.',
    accion: 'Genera automáticamente el expediente técnico con fechas y rubros para sustentar las Solicitudes de Días de Compensación (SDC) o reclamos de mayores costos directos.',
  },
};

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
  if (!aviso) return;
  aviso.textContent = texto;
  aviso.className = `aviso ${tipo}`;
  aviso.hidden = !texto;
  if (texto) aviso.scrollIntoView({ behavior: 'smooth', block: 'center' });
}

function fallo(error) {
  console.error(error);
  const sinConfigurar = SUPABASE_URL.includes('TU-PROYECTO') || SUPABASE_KEY.includes('PEGA-AQUI');
  avisar(sinConfigurar ? 'Falta configurar Supabase en config.js.' : `Error: ${error.message ?? error}`);
}

/* =========================================================
   SISTEMA DE VENTANAS EMERGENTES (MODALES EJECUTIVOS)
   ========================================================= */

function asegurarModalContenedor() {
  let modal = document.getElementById('modal-global');
  if (!modal) {
    modal = document.createElement('div');
    modal.id = 'modal-global';
    modal.className = 'modal-overlay';
    modal.hidden = true;
    modal.innerHTML = `
      <div class="modal-tarjeta" role="dialog" aria-modal="true">
        <header class="modal-cabecera">
          <div>
            <h3 id="modal-titulo" class="modal-titulo"></h3>
            <p id="modal-subtitulo" class="modal-subtitulo"></p>
          </div>
          <button type="button" class="modal-cerrar" onclick="cerrarModal()" aria-label="Cerrar modal">&times;</button>
        </header>
        <div id="modal-cuerpo" class="modal-cuerpo"></div>
        <footer id="modal-pie" class="modal-pie"></footer>
      </div>
    `;
    document.body.appendChild(modal);

    modal.addEventListener('click', e => {
      if (e.target === modal) cerrarModal();
    });

    document.addEventListener('keydown', e => {
      if (e.key === 'Escape' && !modal.hidden) cerrarModal();
    });
  }
  return modal;
}

function abrirModal({ titulo, subtitulo = '', contenidoHtml = '', botonesHtml = '', anchoMax = '620px' }) {
  const modal = asegurarModalContenedor();
  document.getElementById('modal-titulo').innerHTML = titulo;
  const sub = document.getElementById('modal-subtitulo');
  sub.innerHTML = subtitulo;
  sub.hidden = !subtitulo;
  document.getElementById('modal-cuerpo').innerHTML = contenidoHtml;
  
  const pie = document.getElementById('modal-pie');
  pie.innerHTML = botonesHtml;
  pie.hidden = !botonesHtml;

  const tarjeta = modal.querySelector('.modal-tarjeta');
  tarjeta.style.maxWidth = anchoMax;

  modal.hidden = false;
  document.body.style.overflow = 'hidden';
}

function cerrarModal() {
  const modal = document.getElementById('modal-global');
  if (modal) {
    modal.hidden = true;
    document.body.style.overflow = '';
  }
}

function explicarKpi(clave) {
  const info = GLOSARIO_KPIS[clave];
  if (!info) return;

  const html = `
    <div class="glosario-caja">
      <div class="glosario-fila">
        <span class="glosario-etiqueta">¿Qué significa?</span>
        <div class="glosario-texto">${info.queEs}</div>
      </div>
      <div class="glosario-fila">
        <span class="glosario-etiqueta">Fórmula de cálculo:</span>
        <div class="codigo-formula">${info.formula}</div>
      </div>
      <div class="glosario-fila">
        <span class="glosario-etiqueta">Meta corporativa:</span>
        <div><span class="etiqueta ok">${info.meta}</span></div>
      </div>
      <div class="glosario-fila">
        <span class="glosario-etiqueta">Cálculo en Novax:</span>
        <div class="glosario-texto">${info.comoSeCalcula}</div>
      </div>
      <div class="glosario-fila destacada">
        <span class="glosario-etiqueta">🎯 Decisión gerencial:</span>
        <div class="glosario-texto">${info.accion}</div>
      </div>
    </div>
  `;

  abrirModal({
    titulo: `ℹ️ ${info.titulo}`,
    subtitulo: info.subtitulo,
    contenidoHtml: html,
    botonesHtml: `<button type="button" class="btn btn-primario" onclick="cerrarModal()">Entendido</button>`,
    anchoMax: '640px',
  });
}
